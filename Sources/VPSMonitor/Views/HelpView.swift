import SwiftUI
import VPSMonitorCore

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Справка VPSMonitor", "VPSMonitor Help", es: "Ayuda de VPSMonitor", zh: "VPSMonitor 帮助"))
                        .font(.largeTitle.bold())
                    Text(L10n.text(
                        "Краткая инструкция по мониторингу VPS без серверного агента.",
                        "A quick guide to monitoring VPS hosts without a server-side agent.",
                        es: "Guía rápida para monitorizar VPS sin agente en el servidor.",
                        zh: "无需服务器端代理即可监控 VPS 的快速指南。"
                    ))
                    .foregroundStyle(.secondary)
                }

                HelpSection(title: L10n.text("Добавление сервера", "Adding a server", es: "Añadir un servidor", zh: "添加服务器")) {
                    HelpBullet(L10n.text("Откройте File → Add Server или менюбар → Add Server.", "Open File → Add Server or the menu bar → Add Server.", es: "Abra Archivo → Añadir servidor o el menú de la barra → Añadir servidor.", zh: "打开 文件 → 添加服务器，或菜单栏 → 添加服务器。"))
                    HelpBullet(L10n.text("Укажите имя, host/IP, SSH-пользователя и способ подключения.", "Enter name, host/IP, SSH user and authentication method.", es: "Introduzca nombre, host/IP, usuario SSH y método de autenticación.", zh: "输入名称、主机/IP、SSH 用户和认证方式。"))
                    HelpBullet(L10n.text("Страна определяется автоматически по IP, но её можно выбрать вручную.", "Country is detected by IP, but you can override it manually.", es: "El país se detecta por IP, pero puede cambiarlo manualmente.", zh: "国家/地区会通过 IP 自动识别，也可以手动覆盖。"))
                }

                HelpSection(title: L10n.text("Что проверяется", "What is checked", es: "Qué se comprueba", zh: "检查内容")) {
                    HelpBullet(L10n.text("CPU, RAM, диск, аптайм и время полного SSH-опроса.", "CPU, RAM, disk, uptime and full SSH round-trip time.", es: "CPU, RAM, disco, tiempo activo y latencia SSH completa.", zh: "CPU、内存、磁盘、运行时间和完整 SSH 往返耗时。"))
                    HelpBullet(L10n.text("Проекты в /opt, /var/www, /srv, /app, /home/* и живые процессы.", "Projects in /opt, /var/www, /srv, /app, /home/* and live processes.", es: "Proyectos en /opt, /var/www, /srv, /app, /home/* y procesos activos.", zh: "/opt、/var/www、/srv、/app、/home/* 中的项目和运行进程。"))
                    HelpBullet(L10n.text("Остановленные службы, новые проекты и отклонения от обычной нагрузки.", "Stopped services, new projects and deviations from usual load.", es: "Servicios detenidos, proyectos nuevos y desviaciones de la carga habitual.", zh: "停止的服务、新项目和与常规负载的偏差。"))
                }

                HelpSection(title: L10n.text("Безопасность", "Security", es: "Seguridad", zh: "安全")) {
                    HelpBullet(L10n.text("На сервер ничего не устанавливается.", "Nothing is installed on the server.", es: "No se instala nada en el servidor.", zh: "不会在服务器上安装任何内容。"))
                    HelpBullet(L10n.text("Скрипт мониторинга read-only: читает /proc, df, ps и systemctl.", "The monitoring script is read-only: it reads /proc, df, ps and systemctl.", es: "El script de monitorización es de solo lectura: lee /proc, df, ps y systemctl.", zh: "监控脚本为只读：读取 /proc、df、ps 和 systemctl。"))
                    HelpBullet(L10n.text("Пароли хранятся только в macOS Keychain.", "Passwords are stored only in macOS Keychain.", es: "Las contraseñas se guardan solo en macOS Keychain.", zh: "密码仅存储在 macOS Keychain 中。"))
                }

                HelpSection(title: L10n.text("Полезные действия", "Useful actions", es: "Acciones útiles", zh: "常用操作")) {
                    HelpBullet(L10n.text("Cmd+N — добавить VPS.", "Cmd+N — add VPS.", es: "Cmd+N — añadir VPS.", zh: "Cmd+N — 添加 VPS。"))
                    HelpBullet(L10n.text("Shift+Cmd+E — открыть редактирование VPS.", "Shift+Cmd+E — open VPS editing.", es: "Shift+Cmd+E — abrir edición de VPS.", zh: "Shift+Cmd+E — 打开 VPS 编辑。"))
                    HelpBullet(L10n.text("Cmd+/ — открыть эту справку.", "Cmd+/ — open this help.", es: "Cmd+/ — abrir esta ayuda.", zh: "Cmd+/ — 打开此帮助。"))
                }
            }
            .padding(28)
        }
        .frame(width: 620, height: 640)
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }
}

private struct HelpBullet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
