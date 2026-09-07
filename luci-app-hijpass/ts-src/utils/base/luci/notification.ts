import notificationManager from "../../../module/notification";

const NotificationUtils = {
    show: function (options: any) {
        return notificationManager.show(options);
    },

    success: function (title: string, content?: string, duration?: number) {
        return notificationManager.show({ title, content, type: 'success', duration });
    },

    error: function (title: string, content?: string, duration?: number) {
        return notificationManager.show({ title, content, type: 'error', duration });
    },

    warning: function (title: string, content?: string, duration?: number) {
        return notificationManager.show({ title, content, type: 'warning', duration });
    },

    info: function (title: string, content?: string, duration?: number) {
        return notificationManager.show({ title, content, type: 'info', duration });
    },

    clear: function () {
        return notificationManager.clear();
    },
}

export { NotificationUtils }
