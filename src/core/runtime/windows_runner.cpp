#include "windows_runner.h"

#include "proton_manager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStandardPaths>

#if defined(Q_OS_WIN)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shellapi.h>
#endif

namespace arachnel::core {

namespace {

bool runProcess(QProcess& process, int timeoutMs, QString* errorOut)
{
    process.start();
    if (!process.waitForStarted(15000)) {
        if (errorOut) {
            const QString detail = process.errorString().trimmed();
            *errorOut = detail.isEmpty()
                            ? QCoreApplication::translate("Core", "Failed to start: %1")
                                  .arg(process.program())
                            : QCoreApplication::translate("Core", "Failed to start: %1")
                                  .arg(QStringLiteral("%1 (%2)").arg(process.program(), detail));
        }
        return false;
    }
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        if (errorOut)
            *errorOut = QCoreApplication::translate("Core", "Timeout: %1").arg(process.program());
        return false;
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        if (errorOut) {
            const QString stderrText =
                QString::fromLocal8Bit(process.readAllStandardError()).trimmed();
            *errorOut = stderrText.isEmpty()
                            ? QCoreApplication::translate("Core", "%1 exited with code %2")
                                  .arg(process.program())
                                  .arg(process.exitCode())
                            : stderrText;
        }
        return false;
    }
    return true;
}

#if defined(Q_OS_WIN)

QString quoteWindowsArg(const QString& text)
{
    if (text.isEmpty())
        return QStringLiteral("\"\"");

    if (!text.contains(QLatin1Char(' ')) && !text.contains(QLatin1Char('\t'))
        && !text.contains(QLatin1Char('"')))
        return text;

    QString escaped;
    escaped.reserve(text.size() + 4);
    escaped += QLatin1Char('"');
    int backslashes = 0;
    for (const QChar ch : text) {
        if (ch == QLatin1Char('\\')) {
            ++backslashes;
            continue;
        }
        if (ch == QLatin1Char('"')) {
            escaped += QString(backslashes * 2 + 1, QLatin1Char('\\'));
            backslashes = 0;
            escaped += QLatin1Char('"');
            continue;
        }
        if (backslashes > 0) {
            escaped += QString(backslashes, QLatin1Char('\\'));
            backslashes = 0;
        }
        escaped += ch;
    }
    if (backslashes > 0)
        escaped += QString(backslashes * 2, QLatin1Char('\\'));
    escaped += QLatin1Char('"');
    return escaped;
}

QString formatWindowsParameters(const QStringList& arguments)
{
    QStringList parts;
    for (const QString& argument : arguments)
        parts << quoteWindowsArg(argument);
    return parts.join(QLatin1Char(' '));
}

QString describeWin32Error(DWORD error)
{
    if (error == ERROR_CANCELLED)
        return QCoreApplication::translate("Core", "launch cancelled (UAC)");
    if (error == ERROR_ELEVATION_REQUIRED)
        return QCoreApplication::translate("Core", "administrator rights required");
    return QStringLiteral("Win32 %1").arg(error);
}

bool runWindowsNativeProcess(const QString& program, const QStringList& arguments, int timeoutMs,
                             QString* errorOut, const QString& workingDirectory)
{
    if (!QFileInfo::exists(program)) {
        if (errorOut)
            *errorOut = QCoreApplication::translate("Core", "File not found: %1").arg(program);
        return false;
    }

    const QString nativeProgram = QDir::toNativeSeparators(program);
    const QString parameters = formatWindowsParameters(arguments);
    const QString nativeWorkDir =
        workingDirectory.isEmpty() ? QString() : QDir::toNativeSeparators(workingDirectory);

    SHELLEXECUTEINFOW executeInfo{};
    executeInfo.cbSize = sizeof(executeInfo);
    executeInfo.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOZONECHECKS;
    executeInfo.lpVerb = L"open";
    executeInfo.lpFile = reinterpret_cast<LPCWSTR>(nativeProgram.utf16());
    executeInfo.lpParameters = parameters.isEmpty()
                                   ? nullptr
                                   : reinterpret_cast<LPCWSTR>(parameters.utf16());
    executeInfo.lpDirectory = nativeWorkDir.isEmpty()
                                  ? nullptr
                                  : reinterpret_cast<LPCWSTR>(nativeWorkDir.utf16());
    executeInfo.nShow = SW_HIDE;

    if (!ShellExecuteExW(&executeInfo)) {
        if (errorOut) {
            *errorOut = QCoreApplication::translate("Core", "Failed to start %1: %2")
                            .arg(nativeProgram, describeWin32Error(GetLastError()));
        }
        return false;
    }

    if (!executeInfo.hProcess) {
        if (errorOut)
            *errorOut = QCoreApplication::translate("Core", "Could not track installer process");
        return false;
    }

    const DWORD waitResult =
        WaitForSingleObject(executeInfo.hProcess, static_cast<DWORD>(timeoutMs));
    if (waitResult == WAIT_TIMEOUT) {
        TerminateProcess(executeInfo.hProcess, 1);
        CloseHandle(executeInfo.hProcess);
        if (errorOut)
            *errorOut = QCoreApplication::translate("Core", "Timeout: %1").arg(nativeProgram);
        return false;
    }

    DWORD exitCode = 1;
    GetExitCodeProcess(executeInfo.hProcess, &exitCode);
    CloseHandle(executeInfo.hProcess);

    if (exitCode != 0) {
        if (errorOut)
            *errorOut = QCoreApplication::translate("Core", "%1 exited with code %2").arg(nativeProgram).arg(exitCode);
        return false;
    }

    return true;
}

#endif

bool isWindowsExecutable(const QString& path)
{
    return path.endsWith(QStringLiteral(".exe"), Qt::CaseInsensitive);
}

#if defined(Q_OS_LINUX)
QString shellSingleQuote(QString value)
{
    value.replace(QLatin1Char('\''), QStringLiteral("'\"'\"'"));
    return QLatin1Char('\'') + value + QLatin1Char('\'');
}

QString makePluginSafeProtonLauncher(const QString& protonExecutable,
                                     const QString& compatDataPath)
{
    if (protonExecutable.isEmpty())
        return protonExecutable;

    // Keep the helper outside the Proton prefix. Installers/plugins are allowed to recreate or
    // wipe compatDataPath while preparing a fresh prefix; when the helper lived there it could be
    // deleted immediately before QProcess tried to execute it, producing FailedToStart.
    QString runtimeRoot = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (runtimeRoot.isEmpty())
        return protonExecutable;
    runtimeRoot = QDir(runtimeRoot).filePath(QStringLiteral("runtime"));
    if (!QDir().mkpath(runtimeRoot))
        return protonExecutable;

    QString launcherId = QFileInfo(compatDataPath).fileName();
    if (launcherId.isEmpty())
        launcherId = QStringLiteral("default");
    for (QChar& ch : launcherId) {
        if (!ch.isLetterOrNumber() && ch != QLatin1Char('-') && ch != QLatin1Char('_'))
            ch = QLatin1Char('_');
    }

    const QString launcherPath =
        QDir(runtimeRoot).filePath(QStringLiteral("arachnel-proton-launcher-%1").arg(launcherId));
    const QByteArray desired =
        QByteArrayLiteral("#!/bin/sh\n"
                          "unset LD_LIBRARY_PATH STEAM_RUNTIME STEAM_RUNTIME_LIBRARY_PATH\n"
                          "exec ")
        + shellSingleQuote(protonExecutable).toUtf8() + QByteArrayLiteral(" \"$@\"\n");

    bool needsWrite = true;
    QFile existing(launcherPath);
    if (existing.open(QIODevice::ReadOnly)) {
        needsWrite = existing.readAll() != desired;
        existing.close();
    }

    if (needsWrite) {
        QFile launcher(launcherPath);
        if (!launcher.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
            return protonExecutable;
        if (launcher.write(desired) != desired.size()) {
            launcher.close();
            return protonExecutable;
        }
        launcher.close();
    }

    const QFileDevice::Permissions permissions =
        QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
        | QFileDevice::ReadGroup | QFileDevice::ExeGroup | QFileDevice::ReadOther
        | QFileDevice::ExeOther;
    if (!QFile::setPermissions(launcherPath, permissions))
        return protonExecutable;

    return launcherPath;
}

bool configureProtonProcess(QProcess& process, const QString& protonExecutable,
                            const QStringList& protonArgs, QString* errorOut)
{
    const QFileInfo info(protonExecutable);
    if (!info.exists() || !info.isFile()) {
        if (errorOut)
            *errorOut = QCoreApplication::translate("Core", "Proton executable not found: %1")
                            .arg(protonExecutable);
        return false;
    }

    // Proton is a script. Launch it through the interpreter declared by its shebang instead of
    // relying on the executable bit / kernel script handling. Steam Deck installations can keep a
    // perfectly valid Proton script that QProcess otherwise reports as FailedToStart.
    QFile script(protonExecutable);
    if (script.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString firstLine = QString::fromUtf8(script.readLine()).trimmed();
        if (firstLine.startsWith(QStringLiteral("#!"))) {
            QStringList interpreter = QProcess::splitCommand(firstLine.mid(2).trimmed());
            if (!interpreter.isEmpty()) {
                process.setProgram(interpreter.takeFirst());
                QStringList args = interpreter;
                args.append(protonExecutable);
                args.append(protonArgs);
                process.setArguments(args);
                return true;
            }
        }
    }

    if (info.isExecutable()) {
        process.setProgram(protonExecutable);
        process.setArguments(protonArgs);
        return true;
    }

    if (errorOut)
        *errorOut = QCoreApplication::translate("Core", "Proton script is not executable: %1")
                        .arg(protonExecutable);
    return false;
}
#endif

} // namespace

void fillProtonInstallFields(const QString& entryId, const QString& preferredProtonId,
                             QString* protonExecutable, QString* compatDataPath,
                             QString* steamCompatClientPath)
{
#if !defined(Q_OS_LINUX)
    (void)entryId;
    (void)preferredProtonId;
    (void)protonExecutable;
    (void)compatDataPath;
    (void)steamCompatClientPath;
    return;
#else
    if (!protonExecutable || !compatDataPath || !steamCompatClientPath)
        return;

    ProtonManager manager;
    QString resolvedProton = manager.executableForId(preferredProtonId);
    if (resolvedProton.isEmpty())
        resolvedProton = manager.resolveProtonExecutable(preferredProtonId);
    if (resolvedProton.isEmpty())
        return;

    *compatDataPath = manager.compatDataPathForGame(entryId);
    *protonExecutable = makePluginSafeProtonLauncher(resolvedProton, *compatDataPath);
    *steamCompatClientPath = manager.steamCompatClientPath();
#endif
}

bool runWindowsProgramAndWait(const QString& program, const QStringList& arguments, int timeoutMs,
                              QString* errorOut, const QString& workingDirectory,
                              const WindowsRunEnv& env)
{
#if defined(Q_OS_WIN)
    (void)env;
    return runWindowsNativeProcess(program, arguments, timeoutMs, errorOut, workingDirectory);
#else
    if (!QFileInfo::exists(program)) {
        if (errorOut)
            *errorOut = QCoreApplication::translate("Core", "File not found: %1").arg(program);
        return false;
    }

    QString workDir = workingDirectory;
    if (workDir.isEmpty())
        workDir = QFileInfo(program).absolutePath();

    if (!isWindowsExecutable(program)) {
        QProcess process;
        process.setProgram(program);
        process.setArguments(arguments);
        process.setWorkingDirectory(workDir);
        return runProcess(process, timeoutMs, errorOut);
    }

    if (!env.useProton()) {
        if (errorOut) {
            *errorOut = QStringLiteral(
                "Для установки Windows-установщика нужен Proton (Настройки → Запуск)");
        }
        return false;
    }

    QProcessEnvironment qenv = QProcessEnvironment::systemEnvironment();
    // Steam-runtime on LD_LIBRARY_PATH breaks /usr/bin/env in the Proton script.
    qenv.remove(QStringLiteral("LD_LIBRARY_PATH"));
    qenv.remove(QStringLiteral("STEAM_RUNTIME"));
    qenv.remove(QStringLiteral("STEAM_RUNTIME_LIBRARY_PATH"));
    if (!env.steamCompatClientPath.isEmpty())
        qenv.insert(QStringLiteral("STEAM_COMPAT_CLIENT_INSTALL_PATH"), env.steamCompatClientPath);
    if (!env.compatDataPath.isEmpty())
        qenv.insert(QStringLiteral("STEAM_COMPAT_DATA_PATH"), env.compatDataPath);
    qenv.insert(QStringLiteral("WINEDEBUG"), QStringLiteral("-all"));

    QStringList protonArgs = {QStringLiteral("run"), program};
    protonArgs += arguments;

    QProcess process;
    if (!configureProtonProcess(process, env.protonExecutable, protonArgs, errorOut))
        return false;
    process.setWorkingDirectory(workDir);
    process.setProcessEnvironment(qenv);
    return runProcess(process, timeoutMs, errorOut);
#endif
}

} // namespace arachnel::core
