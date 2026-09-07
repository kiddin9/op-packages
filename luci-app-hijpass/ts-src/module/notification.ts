/**
 * 右侧滑动弹窗通知组件
 * 支持成功、错误、警告、信息四种类型
 */

export interface NotificationOptions {
    message?: string; // 兼容旧版本，如果只传 message 则作为 title
    title?: string; // 通知标题
    content?: string; // 通知内容
    type?: 'success' | 'error' | 'warning' | 'info';
    duration?: number; // 毫秒，0 表示不自动关闭
    icon?: boolean; // 是否显示图标
}

class NotificationManager {
    private container: HTMLElement | null = null;
    private notifications: Map<string, HTMLElement> = new Map();
    private notificationId: number = 0;
    private autoCloseTimers: Map<string, any> = new Map();

    constructor() {
        this.initContainer();
    }

    /**
     * 初始化通知容器
     */
    private initContainer() {
        if (this.container) return;

        this.container = document.createElement('div');
        this.container.id = 'notification-container';
        this.container.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 9999;
            pointer-events: none;
        `;
        document.body.appendChild(this.container);
    }

    /**
     * 获取通知类型对应的颜色和图标
     */
    private getTypeConfig(type: string) {
        const configs: Record<string, any> = {
            success: {
                bgColor: '#4caf50',
                borderColor: '#45a049',
                icon: '✓',
                textColor: '#fff'
            },
            error: {
                bgColor: '#f44336',
                borderColor: '#da190b',
                icon: '✕',
                textColor: '#fff'
            },
            warning: {
                bgColor: '#ff9800',
                borderColor: '#e68900',
                icon: '⚠',
                textColor: '#fff'
            },
            info: {
                bgColor: '#2196f3',
                borderColor: '#0b7dda',
                icon: 'ℹ',
                textColor: '#fff'
            }
        };
        return configs[type] || configs.info;
    }

    /**
     * 显示通知
     */
    show(options: NotificationOptions) {
        const {
            message,
            title,
            content,
            type = 'info',
            duration = 3000,
            icon = false
        } = options;

        this.initContainer();

        const id = `notification-${++this.notificationId}`;
        const config = this.getTypeConfig(type);

        // 确定标题和内容
        // 如果提供了 title 和 content，使用它们
        // 否则，如果提供了 message，使用 message 作为标题
        const notificationTitle = title || message;
        const notificationContent = content;

        // 创建通知元素
        const notification = document.createElement('div');
        notification.id = id;
        notification.style.cssText = `
            background-color: ${config.bgColor};
            border-left: 4px solid ${config.borderColor};
            color: ${config.textColor};
            padding: 16px 20px;
            margin-bottom: 10px;
            border-radius: 4px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
            display: flex;
            align-items: flex-start;
            gap: 12px;
            min-width: 300px;
            max-width: 400px;
            word-break: break-word;
            animation: slideInRight 0.3s ease-out;
            pointer-events: auto;
            transition: all 0.3s ease;
            font-size: 14px;
            font-weight: 500;
        `;

        // 创建图标
        if (icon) {
            const iconEl = document.createElement('span');
            iconEl.style.cssText = `
                font-size: 20px;
                font-weight: bold;
                flex-shrink: 0;
                display: flex;
                align-items: center;
                justify-content: center;
                width: 24px;
                height: 24px;
                margin-top: 2px;
            `;
            iconEl.textContent = config.icon;
            notification.appendChild(iconEl);
        }

        // 创建内容容器
        const contentContainer = document.createElement('div');
        contentContainer.style.cssText = `
            flex: 1;
            display: flex;
            flex-direction: column;
            gap: 4px;
        `;

        // 创建标题
        if (notificationTitle) {
            const titleEl = document.createElement('div');
            titleEl.style.cssText = `
                font-weight: 600;
                font-size: 14px;
                line-height: 1.4;
            `;
            titleEl.textContent = notificationTitle;
            contentContainer.appendChild(titleEl);
        }

        // 创建内容
        if (notificationContent) {
            const contentEl = document.createElement('div');
            contentEl.style.cssText = `
                font-weight: 400;
                font-size: 13px;
                line-height: 1.4;
                opacity: 0.9;
                white-space: pre-line;
            `;
            contentEl.textContent = notificationContent;
            contentContainer.appendChild(contentEl);
        }

        notification.appendChild(contentContainer);

        // 创建关闭按钮
        const closeBtn = document.createElement('button');
        closeBtn.style.cssText = `
            background: none;
            border: none;
            color: ${config.textColor};
            cursor: pointer;
            font-size: 20px;
            padding: 0;
            width: 24px;
            height: 24px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
            opacity: 0.7;
            transition: opacity 0.2s;
        `;
        closeBtn.innerHTML = '×';
        closeBtn.onmouseover = () => closeBtn.style.opacity = '1';
        closeBtn.onmouseout = () => closeBtn.style.opacity = '0.7';
        closeBtn.onclick = (e) => {
            e.stopPropagation();
            this.remove(id);
        };
        notification.appendChild(closeBtn);

        // 添加到容器
        this.container!.appendChild(notification);
        this.notifications.set(id, notification);

        // 自动关闭
        if (duration > 0) {
            const timer = setTimeout(() => {
                this.remove(id);
            }, duration);
            this.autoCloseTimers.set(id, timer);

            // 鼠标悬停时暂停自动关闭
            notification.onmouseenter = () => {
                const existingTimer = this.autoCloseTimers.get(id);
                if (existingTimer) {
                    clearTimeout(existingTimer);
                    this.autoCloseTimers.delete(id);
                }
            };

            // 鼠标离开时恢复自动关闭
            notification.onmouseleave = () => {
                if (this.notifications.has(id)) {
                    const newTimer = setTimeout(() => {
                        this.remove(id);
                    }, duration);
                    this.autoCloseTimers.set(id, newTimer);
                }
            };
        }

        return id;
    }

    /**
     * 移除通知
     */
    private remove(id: string) {
        const notification = this.notifications.get(id);
        if (!notification) return;

        // 清除自动关闭定时器
        const timer = this.autoCloseTimers.get(id);
        if (timer) {
            clearTimeout(timer);
            this.autoCloseTimers.delete(id);
        }

        notification.style.animation = 'slideOutRight 0.3s ease-in';
        notification.style.opacity = '0';

        setTimeout(() => {
            notification.remove();
            this.notifications.delete(id);
        }, 300);
    }

    /**
     * 显示成功通知
     */
    success(message: string, duration?: number) {
        return this.show({ message, type: 'success', duration });
    }

    /**
     * 显示错误通知
     */
    error(message: string, duration?: number) {
        return this.show({ message, type: 'error', duration });
    }

    /**
     * 显示警告通知
     */
    warning(message: string, duration?: number) {
        return this.show({ message, type: 'warning', duration });
    }

    /**
     * 显示信息通知
     */
    info(message: string, duration?: number) {
        return this.show({ message, type: 'info', duration });
    }

    /**
     * 清空所有通知
     */
    clear() {
        this.notifications.forEach((_, id) => {
            this.remove(id);
        });
    }
}

// 创建全局单例
const notificationManager = new NotificationManager();

// 注入 CSS 动画
function injectStyles() {
    if (document.getElementById('notification-styles')) return;

    const style = document.createElement('style');
    style.id = 'notification-styles';
    style.textContent = `
        @keyframes slideInRight {
            from {
                transform: translateX(400px);
                opacity: 0;
            }
            to {
                transform: translateX(0);
                opacity: 1;
            }
        }

        @keyframes slideOutRight {
            from {
                transform: translateX(0);
                opacity: 1;
            }
            to {
                transform: translateX(400px);
                opacity: 0;
            }
        }

        @media (max-width: 768px) {
            #notification-container {
                left: 10px !important;
                right: 10px !important;
                top: 10px !important;
            }

            #notification-container > div {
                min-width: auto !important;
                max-width: 100% !important;
            }
        }
    `;
    document.head.appendChild(style);
}

// 页面加载时注入样式
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectStyles);
} else {
    injectStyles();
}

export default notificationManager;
