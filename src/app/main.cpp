#include <QCoreApplication>
#include <QDir>
#include <QEvent>
#include <QGuiApplication>
#include <QIcon>
#include <QKeyEvent>
#include <QPixmapCache>
#include <QQmlApplicationEngine>
#include <QQmlError>
#include <QStyleHints>
#include <QString>
#include <QTimer>
#include <QWindow>
#include <array>
#include <cerrno>
#include <cstdio>

#if !defined(Q_OS_WIN)
#include <QApplication>
#else
#include <QGuiApplication>
#endif

#if defined(Q_OS_LINUX)
#include <fcntl.h>
#include <linux/joystick.h>
#include <unistd.h>
#endif

#include "core/facade/core_controller.h"
#include "core/settings/settings_store.h"
#include "core/i18n/translation_service.h"
#include "crash_log.h"
#include "deep_link.h"
#include "settings_identity.h"

#ifndef QT_QML_MATERIAL_IMPORT_PATH
#define QT_QML_MATERIAL_IMPORT_PATH ""
#endif

namespace {

#if defined(Q_OS_LINUX)
class LinuxGamepadKeyBridge final : public QObject {
public:
    explicit LinuxGamepadKeyBridge(QObject* parent = nullptr)
        : QObject(parent)
    {
        m_pollTimer.setInterval(8);
        QObject::connect(&m_pollTimer, &QTimer::timeout, this, [this]() { pollController(); });
        m_pollTimer.start();

        m_rescanTimer.setInterval(1500);
        QObject::connect(&m_rescanTimer, &QTimer::timeout, this, [this]() { tryOpenController(); });
        m_rescanTimer.start();

        m_repeatDelay.setSingleShot(true);
        m_repeatDelay.setInterval(320);
        QObject::connect(&m_repeatDelay, &QTimer::timeout, this, [this]() {
            if (m_repeatKey != 0)
                m_repeatTimer.start();
        });

        m_repeatTimer.setInterval(90);
        QObject::connect(&m_repeatTimer, &QTimer::timeout, this, [this]() {
            if (m_repeatKey != 0)
                dispatchKey(m_repeatKey);
        });

        tryOpenController();
    }

    ~LinuxGamepadKeyBridge() override
    {
        closeController();
    }

private:
    static int directionForValue(qint16 value)
    {
        constexpr int deadZone = 16000;
        if (value > deadZone)
            return 1;
        if (value < -deadZone)
            return -1;
        return 0;
    }

    QObject* keyTarget() const
    {
        if (QObject* focus = QGuiApplication::focusObject())
            return focus;
        if (QWindow* window = QGuiApplication::focusWindow())
            return window;
        return nullptr;
    }

    void dispatchKey(int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier)
    {
        QObject* target = keyTarget();
        if (!target)
            return;

        QCoreApplication::postEvent(
            target, new QKeyEvent(QEvent::KeyPress, key, modifiers));
        QCoreApplication::postEvent(
            target, new QKeyEvent(QEvent::KeyRelease, key, modifiers));
    }

    void beginRepeat(int key)
    {
        m_repeatTimer.stop();
        m_repeatDelay.stop();
        m_repeatKey = key;
        if (key != 0) {
            dispatchKey(key);
            m_repeatDelay.start();
        }
    }

    void stopRepeatIf(int key)
    {
        if (m_repeatKey != key)
            return;
        m_repeatKey = 0;
        m_repeatDelay.stop();
        m_repeatTimer.stop();
    }

    static int keyForAxis(int axis, int direction)
    {
        if (direction == 0)
            return 0;
        if (axis == 0 || axis == 6)
            return direction < 0 ? Qt::Key_Left : Qt::Key_Right;
        if (axis == 1 || axis == 7)
            return direction < 0 ? Qt::Key_Up : Qt::Key_Down;
        return 0;
    }

    void handleAxis(unsigned char axis, qint16 value)
    {
        if (axis >= m_axisDirection.size())
            return;
        if (axis != 0 && axis != 1 && axis != 6 && axis != 7)
            return;

        const int oldDirection = m_axisDirection[axis];
        const int newDirection = directionForValue(value);
        if (oldDirection == newDirection)
            return;

        const int oldKey = keyForAxis(axis, oldDirection);
        const int newKey = keyForAxis(axis, newDirection);
        m_axisDirection[axis] = newDirection;

        if (newKey != 0)
            beginRepeat(newKey);
        else if (oldKey != 0)
            stopRepeatIf(oldKey);
    }

    void handleButton(unsigned char button, bool pressed)
    {
        if (!pressed)
            return;

        // Steam Input's virtual Xbox layout and the Deck's Linux joystick layout
        // both use the standard face-button order here.
        switch (button) {
        case 0: // A
            dispatchKey(Qt::Key_Return);
            break;
        case 1: // B
            dispatchKey(Qt::Key_Escape);
            break;
        case 2: // X
            dispatchKey(Qt::Key_Space);
            break;
        case 4: // L1
            dispatchKey(Qt::Key_Backtab, Qt::ShiftModifier);
            break;
        case 5: // R1
            dispatchKey(Qt::Key_Tab);
            break;
        case 6: // View / Back
            dispatchKey(Qt::Key_Escape);
            break;
        default:
            break;
        }
    }

    void handleEvent(const js_event& event)
    {
        if (event.type & JS_EVENT_INIT)
            return;

        const unsigned char type = event.type & ~JS_EVENT_INIT;
        if (type == JS_EVENT_AXIS)
            handleAxis(event.number, event.value);
        else if (type == JS_EVENT_BUTTON)
            handleButton(event.number, event.value != 0);
    }

    void tryOpenController()
    {
        if (m_fd >= 0)
            return;

        for (int i = 0; i < 8; ++i) {
            const QByteArray path = QByteArrayLiteral("/dev/input/js") + QByteArray::number(i);
            const int fd = ::open(path.constData(), O_RDONLY | O_NONBLOCK);
            if (fd < 0)
                continue;

            m_fd = fd;
            m_axisDirection.fill(0);
            std::fprintf(stderr, "Arachnel: controller input active on %s\n", path.constData());
            std::fflush(stderr);
            return;
        }
    }

    void closeController()
    {
        if (m_fd >= 0) {
            ::close(m_fd);
            m_fd = -1;
        }
        m_axisDirection.fill(0);
        m_repeatKey = 0;
        m_repeatDelay.stop();
        m_repeatTimer.stop();
    }

    void pollController()
    {
        if (m_fd < 0) {
            tryOpenController();
            return;
        }

        for (;;) {
            js_event event{};
            const ssize_t readSize = ::read(m_fd, &event, sizeof(event));
            if (readSize == static_cast<ssize_t>(sizeof(event))) {
                handleEvent(event);
                continue;
            }

            if (readSize < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
                break;

            if (readSize == 0 || (readSize < 0 && errno != EINTR))
                closeController();
            break;
        }
    }

    int m_fd = -1;
    std::array<int, 8> m_axisDirection{};
    int m_repeatKey = 0;
    QTimer m_pollTimer;
    QTimer m_rescanTimer;
    QTimer m_repeatDelay;
    QTimer m_repeatTimer;
};
#endif

void configureSteamDeckPlatform()
{
#if defined(Q_OS_LINUX)
    const QByteArray qpa = qgetenv("QT_QPA_PLATFORM").trimmed().toLower();
    const QByteArray desktop = qgetenv("XDG_CURRENT_DESKTOP").toLower();
    const bool inGamescope = !qgetenv("GAMESCOPE_WAYLAND_DISPLAY").isEmpty()
        || !qgetenv("SteamGamepadUI").isEmpty()
        || desktop.contains("gamescope");

    // The packaged AppImage defaults to xcb. Inside Steam Gaming Mode that
    // unnecessarily pins Qt to XWayland and can leave the launcher with a dead
    // X11 connection when Gamescope changes focus/surfaces. Let Qt select the
    // native platform in Gamescope instead. Desktop sessions keep the original
    // packaged default and users can still explicitly choose a QPA platform.
    if (inGamescope && qpa == "xcb")
        qunsetenv("QT_QPA_PLATFORM");
#endif
}

void configureQmlEngine(QQmlApplicationEngine& engine)
{
    const QString appDir = QCoreApplication::applicationDirPath();
    engine.addImportPath(appDir + QStringLiteral("/qml"));
    engine.addImportPath(appDir + QStringLiteral("/qml_modules"));

    const QByteArray materialPathEnv = qgetenv("QT_QML_MATERIAL_IMPORT_PATH");
    const QString materialPath = materialPathEnv.isEmpty()
        ? QStringLiteral(QT_QML_MATERIAL_IMPORT_PATH)
        : QString::fromLocal8Bit(materialPathEnv);
    if (!materialPath.isEmpty()) {
        const QString resolved = QDir::isAbsolutePath(materialPath)
            ? materialPath
            : (appDir + QLatin1Char('/') + materialPath);
        engine.addImportPath(resolved);
    }
}

void wireEngineLogging(QQmlApplicationEngine& engine, QCoreApplication& app)
{
    QObject::connect(
        &engine,
        &QQmlEngine::warnings,
        &app,
        [](const QList<QQmlError>& errors) {
            for (const QQmlError& error : errors)
                arachnel::logQmlWarning(error.url(), error.line(), error.column(),
                                        error.description());
        });

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() {
            fprintf(stderr, "Failed to load arachnel QML entry point\n");
            fflush(stderr);
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
}

void applyTranslations(QQmlApplicationEngine& engine, QCoreApplication& app)
{
    auto& core = arachnel::core::CoreController::instance();
    auto& translations = arachnel::core::TranslationService::instance();
    translations.setEngine(&engine);
    translations.applyLanguage(core.settings()->uiLanguage());

    QObject::connect(core.settings(), &arachnel::core::SettingsStore::uiLanguageChanged, &app,
                     [&translations, &core]() {
                         translations.applyLanguage(core.settings()->uiLanguage());
                         core.jobs()->refreshLocalizedText();
                     });
}

} // namespace

int main(int argc, char* argv[])
{
    configureSteamDeckPlatform();

#if !defined(Q_OS_WIN)
    QApplication app(argc, argv);
#else
    QGuiApplication app(argc, argv);
#endif

#if defined(Q_OS_LINUX)
    LinuxGamepadKeyBridge gamepadBridge(&app);
#endif

    arachnel::configureApplicationIdentity();

    const bool crashDialogMode = arachnel::isCrashDialogMode(argc, argv);

    arachnel::installCrashLogging();
    arachnel::logRunStarted(argc, argv);

    const QIcon windowIcon = []() {
        QIcon icon;
        for (const int size : {16, 24, 32, 48, 64, 128, 256, 512}) {
            icon.addFile(QStringLiteral(":/icons/%1.png").arg(size), QSize(size, size));
        }
        return icon;
    }();
    if (!windowIcon.isNull())
        app.setWindowIcon(windowIcon);

    arachnel::core::registerCoreTypes();
    QPixmapCache::setCacheLimit(24 * 1024);

    arachnel::SingleInstanceGuard* singleInstance = nullptr;
    if (!crashDialogMode) {
        arachnel::registerGameDeepLinkProtocol();

        singleInstance = new arachnel::SingleInstanceGuard(&app);
        const QString launchLink = arachnel::findDeepLinkArgument(app.arguments());
        if (!singleInstance->tryBecomePrimary()) {
            singleInstance->forwardToPrimary(launchLink);
            return 0;
        }

        QObject::connect(singleInstance, &arachnel::SingleInstanceGuard::messageReceived, &app,
                         [](const QString& url) {
                             arachnel::core::CoreController::instance().requestDeepLink(url);
                         });

        if (!launchLink.isEmpty())
            arachnel::core::CoreController::instance().requestDeepLink(launchLink);
    }

    int exitCode = 1;
    {
        QQmlApplicationEngine engine;
        configureQmlEngine(engine);
        wireEngineLogging(engine, app);

        if (!crashDialogMode) {
            if (auto* guiApp = qobject_cast<QGuiApplication*>(&app))
                guiApp->setQuitOnLastWindowClosed(true);
            QObject::connect(&app, &QCoreApplication::aboutToQuit, &app, []() {
                arachnel::markApplicationShuttingDown();
            });
        } else {
            arachnel::core::CoreController::setCrashReporterMode(true);
            if (auto* guiApp = qobject_cast<QGuiApplication*>(&app))
                guiApp->setQuitOnLastWindowClosed(true);
            QObject::connect(&app, &QCoreApplication::aboutToQuit, &app, []() {
                arachnel::markApplicationShuttingDown();
            });
        }

        if (crashDialogMode)
            engine.loadFromModule(QStringLiteral("arachnel"), QStringLiteral("CrashReportWindow"));
        else
            engine.loadFromModule(QStringLiteral("arachnel"), QStringLiteral("Main"));

        if (!crashDialogMode) {
            applyTranslations(engine, app);
            QTimer::singleShot(0, &app, []() { arachnel::startHangWatchdog(); });
            const QStringList args = app.arguments();
            const int updateAt = args.indexOf(QStringLiteral("--update"));
            if (updateAt >= 0 && updateAt + 1 < args.size()) {
                const QString entryId = args.at(updateAt + 1);
                QTimer::singleShot(12000, [entryId]() {
                    arachnel::core::CoreController::instance().updateCatalogEntry(entryId);
                });
            }
        }

        exitCode = app.exec();

        // Tear down QML while Core is still alive, then shut Core down, then
        // destroy the engine. Destroying QQmlEngine while plugins/sessions are
        // mid-teardown caused free(): invalid size on Linux (NixOS AppImage).
        arachnel::markApplicationShuttingDown();
        const QList<QObject*> roots = engine.rootObjects();
        for (QObject* root : roots)
            delete root;
        engine.clearComponentCache();

        if (!crashDialogMode)
            arachnel::core::CoreController::instance().prepareShutdown();
    }

    arachnel::logRunFinished(exitCode);
    return exitCode;
}
