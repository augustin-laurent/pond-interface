#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDBusUnixFileDescriptor>
#include <QObject>
#include <QtQml/qqmlregistration.h>

class Logind : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool sleepInhibited READ sleepInhibited WRITE setSleepInhibited NOTIFY sleepInhibitedChanged)
    Q_PROPERTY(bool preparingForSleep READ preparingForSleep NOTIFY preparingForSleepChanged)

public:
    explicit Logind(QObject *parent = nullptr) : QObject(parent) {
        auto bus = QDBusConnection::systemBus();
        bus.connect(service, managerPath, managerInterface, "PrepareForSleep", this, SLOT(prepareForSleep(bool)));
        auto call = QDBusMessage::createMethodCall(service, managerPath, managerInterface, "GetSession");
        call << QStringLiteral("auto");
        QDBusReply<QDBusObjectPath> session = bus.call(call);
        if (session.isValid())
            bus.connect(service, session.value().path(), "org.freedesktop.login1.Session", "Lock", this, SIGNAL(lockRequested()));
    }
    bool sleepInhibited() const { return m_inhibitor.isValid(); }
    bool preparingForSleep() const { return m_preparingForSleep; }
    void setSleepInhibited(bool inhibited) {
        if (inhibited == sleepInhibited())
            return;
        if (inhibited) {
            auto call = QDBusMessage::createMethodCall(service, managerPath, managerInterface, "Inhibit");
            call << "sleep" << "Pond" << "Lock before sleep" << "delay";
            m_inhibitor = QDBusReply<QDBusUnixFileDescriptor>(QDBusConnection::systemBus().call(call)).value();
        } else {
            m_inhibitor = {};
        }
        emit sleepInhibitedChanged();
    }

signals:
    void sleepInhibitedChanged();
    void preparingForSleepChanged();
    void lockRequested();

private slots:
    void prepareForSleep(bool preparing) {
        m_preparingForSleep = preparing;
        emit preparingForSleepChanged();
    }

private:
    static constexpr auto service = "org.freedesktop.login1";
    static constexpr auto managerPath = "/org/freedesktop/login1";
    static constexpr auto managerInterface = "org.freedesktop.login1.Manager";
    QDBusUnixFileDescriptor m_inhibitor;
    bool m_preparingForSleep = false;
};
