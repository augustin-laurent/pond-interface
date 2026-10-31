#pragma once

#include <QGuiApplication>
#include <QObject>
#include <QtQml/qqmlregistration.h>
#include <unistd.h>
#include <wayland-client.h>

// Qt doesn't expose lock modifiers, so listen on a wl_keyboard of our own. The
// compositor sends them whenever one of our surfaces gains keyboard focus.
class CapsLock : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
    explicit CapsLock(QObject *parent = nullptr) : QObject(parent) {
        auto *wayland = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        // Asking a seat without a keyboard for one is a fatal protocol error.
        if (wayland && wayland->keyboard()) {
            m_keyboard = wl_seat_get_keyboard(wayland->seat());
            wl_keyboard_add_listener(m_keyboard, &listener, this);
        }
    }
    ~CapsLock() override {
        if (m_keyboard)
            wl_keyboard_destroy(m_keyboard);
    }
    bool active() const { return m_active; }

signals:
    void activeChanged();

private:
    void setActive(bool active) {
        if (m_active != active) {
            m_active = active;
            emit activeChanged();
        }
    }
    static inline const wl_keyboard_listener listener = {
        .keymap = [](void *, wl_keyboard *, uint32_t, int32_t fd, uint32_t) { close(fd); },
        .enter = [](void *, wl_keyboard *, uint32_t, wl_surface *, wl_array *) {},
        .leave = [](void *, wl_keyboard *, uint32_t, wl_surface *) {},
        .key = [](void *, wl_keyboard *, uint32_t, uint32_t, uint32_t, uint32_t) {},
        // xkb's real modifiers have fixed indices; Lock is always bit 1.
        .modifiers = [](void *data, wl_keyboard *, uint32_t, uint32_t, uint32_t, uint32_t locked, uint32_t) {
            static_cast<CapsLock *>(data)->setActive(locked & (1 << 1));
        },
        .repeat_info = [](void *, wl_keyboard *, int32_t, int32_t) {},
    };
    wl_keyboard *m_keyboard = nullptr;
    bool m_active = false;
};
