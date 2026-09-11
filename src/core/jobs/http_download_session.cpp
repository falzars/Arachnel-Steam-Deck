#include "http_download_session.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>

namespace arachnel::core {

struct HttpDownloadSession::Impl {
    struct ActiveDownload {
        QNetworkReply* reply = nullptr;
        QFile* file = nullptr;
        QString tempPath;
        QString saveDirectory;
        QString writeError;
    };

    QNetworkAccessManager network;
    QHash<QString, ActiveDownload> downloads;
};

namespace {

QString filenameFromContentDisposition(const QString& header)
{
    const QRegularExpression re(QStringLiteral(R"(filename\*?=(?:UTF-8''|")?([^";]+))"),
                                QRegularExpression::CaseInsensitiveOption);
    const auto match = re.match(header);
    if (!match.hasMatch())
        return {};
    return QUrl::fromPercentEncoding(match.captured(1).toUtf8());
}

QString sanitizeFileName(QString name)
{
    name.replace(QRegularExpression(QStringLiteral(R"([<>:"/\\|?*])")), QStringLiteral("_"));
    return name.trimmed();
}

QString tempFileNameForJob(QString jobId)
{
    jobId.replace(QRegularExpression(QStringLiteral(R"([^A-Za-z0-9_.-])")), QStringLiteral("_"));
    return QStringLiteral(".arachnel-%1.part").arg(jobId);
}

} // namespace

HttpDownloadSession::HttpDownloadSession(QObject* parent)
    : QObject(parent)
    , m_impl(new Impl)
{
}

HttpDownloadSession::~HttpDownloadSession()
{
    shutdown();
}

void HttpDownloadSession::shutdown()
{
    if (!m_impl)
        return;

    const auto active = m_impl->downloads;
    m_impl->downloads.clear();
    for (auto it = active.cbegin(); it != active.cend(); ++it) {
        const Impl::ActiveDownload& download = it.value();
        if (download.reply) {
            download.reply->disconnect(this);
            download.reply->abort();
            delete download.reply;
        }
        if (download.file) {
            download.file->close();
            delete download.file;
        }
        if (!download.tempPath.isEmpty())
            QFile::remove(download.tempPath);
    }

    delete m_impl;
    m_impl = nullptr;
}

bool HttpDownloadSession::addJob(const QString& jobId, const QString& url, const QString& referer,
                                 const QString& saveDirectory)
{
    if (!m_impl)
        return false;
    if (jobId.isEmpty() || url.isEmpty() || saveDirectory.isEmpty())
        return false;
    if (m_impl->downloads.contains(jobId))
        return false;

    if (!QDir().mkpath(saveDirectory))
        return false;

    const QString tempPath = QDir(saveDirectory).absoluteFilePath(tempFileNameForJob(jobId));
    QFile::remove(tempPath);
    auto* output = new QFile(tempPath);
    if (!output->open(QIODevice::WriteOnly)) {
        delete output;
        return false;
    }

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Arachnel/0.1"));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    if (!referer.isEmpty())
        request.setRawHeader("Referer", referer.toUtf8());

    QNetworkReply* reply = m_impl->network.get(request);
    Impl::ActiveDownload active;
    active.reply = reply;
    active.file = output;
    active.tempPath = tempPath;
    active.saveDirectory = saveDirectory;
    m_impl->downloads.insert(jobId, active);

    connect(reply, &QNetworkReply::downloadProgress, this,
            [this, jobId](qint64 received, qint64 total) {
                if (!m_impl || !m_impl->downloads.contains(jobId))
                    return;
                const int progress = total > 0
                    ? static_cast<int>((received * 100) / total)
                    : 0;
                emit httpProgress(jobId, progress, received, total);
            });

    connect(reply, &QIODevice::readyRead, this, [this, jobId, reply]() {
        if (!m_impl)
            return;
        auto it = m_impl->downloads.find(jobId);
        if (it == m_impl->downloads.end() || it->reply != reply || !it->file)
            return;
        if (!it->writeError.isEmpty()) {
            reply->readAll();
            return;
        }

        const QByteArray data = reply->readAll();
        if (data.isEmpty())
            return;
        const qint64 written = it->file->write(data);
        if (written != data.size()) {
            it->writeError = it->file->errorString();
            if (it->writeError.isEmpty())
                it->writeError = QCoreApplication::translate("Core", "Failed to save file");
            reply->abort();
        }
    });

    connect(reply, &QNetworkReply::finished, this, [this, jobId, reply]() {
        if (!m_impl) {
            reply->deleteLater();
            return;
        }

        auto it = m_impl->downloads.find(jobId);
        if (it == m_impl->downloads.end()) {
            reply->deleteLater();
            return;
        }
        Impl::ActiveDownload download = it.value();
        m_impl->downloads.erase(it);

        // readyRead normally drained the reply already, but consume any tail that
        // arrived with finished before closing the file.
        if (download.file && download.writeError.isEmpty()) {
            const QByteArray tail = reply->readAll();
            if (!tail.isEmpty() && download.file->write(tail) != tail.size()) {
                download.writeError = download.file->errorString();
                if (download.writeError.isEmpty())
                    download.writeError = QCoreApplication::translate("Core", "Failed to save file");
            }
            download.file->flush();
            download.file->close();
        }

        const QNetworkReply::NetworkError networkError = reply->error();
        const QString networkErrorString = reply->errorString();
        const QString contentDisposition =
            reply->header(QNetworkRequest::ContentDispositionHeader).toString();
        const QUrl finalUrl = reply->url();
        reply->deleteLater();
        delete download.file;
        download.file = nullptr;

        if (!download.writeError.isEmpty() || networkError != QNetworkReply::NoError) {
            QFile::remove(download.tempPath);
            emit httpFailed(jobId, !download.writeError.isEmpty()
                                      ? download.writeError
                                      : networkErrorString);
            return;
        }

        QString fileName = filenameFromContentDisposition(contentDisposition);
        if (fileName.isEmpty())
            fileName = QFileInfo(finalUrl.path()).fileName();
        fileName = sanitizeFileName(fileName);
        if (fileName.isEmpty())
            fileName = QStringLiteral("download.bin");

        const QString filePath = QDir(download.saveDirectory).absoluteFilePath(fileName);
        if (QFileInfo::exists(filePath) && !QFile::remove(filePath)) {
            QFile::remove(download.tempPath);
            emit httpFailed(jobId, QCoreApplication::translate("Core", "Failed to replace downloaded file"));
            return;
        }
        if (!QFile::rename(download.tempPath, filePath)) {
            QFile::remove(download.tempPath);
            emit httpFailed(jobId, QCoreApplication::translate("Core", "Failed to finalize downloaded file"));
            return;
        }

        emit httpFinished(jobId, filePath);
    });

    return true;
}

void HttpDownloadSession::cancel(const QString& jobId)
{
    if (!m_impl)
        return;
    auto it = m_impl->downloads.find(jobId);
    if (it == m_impl->downloads.end())
        return;

    const Impl::ActiveDownload download = it.value();
    m_impl->downloads.erase(it);

    if (download.reply) {
        // Disconnect first so abort() cannot re-enter finished while the active
        // record is being torn down.
        download.reply->disconnect(this);
        download.reply->abort();
        download.reply->deleteLater();
    }
    if (download.file) {
        download.file->close();
        delete download.file;
    }
    if (!download.tempPath.isEmpty())
        QFile::remove(download.tempPath);
}

} // namespace arachnel::core
