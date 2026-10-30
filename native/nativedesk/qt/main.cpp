/*
 * Qt demo for the native desktop test. NativeDesk.kt starts QtHost.kt in its
 * own app_process, which loads this library (libnativedesk_qt.so) and calls
 * QtHost.run(): Qt for Android needs a Java VM. Two ordinary Qt windows:
 *   - "Qt raster": QPainter in software (QRasterWindow), like Qt Widgets
 *   - "Qt OpenGL": QPainter on the GPU (QOpenGLWindow), the path Qt Quick
 *     and so Plasma use
 * Both animate every frame, show their frame rate and follow the pointer;
 * typing goes into the raster window's text line.
 */
#include <QtCore/QElapsedTimer>
#include <QtCore/QtPlugin>
#include <QtGui/QGuiApplication>
#include <QtGui/QKeyEvent>
#include <QtGui/QMouseEvent>
#include <QtGui/QOpenGLFunctions>
#include <QtGui/QPainter>
#include <QtGui/QRasterWindow>
#include <QtGui/QSurfaceFormat>
#include <QtOpenGL/QOpenGLWindow>
#include <cmath>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <jni.h>
#include <vector>
#include <string>
#include <unistd.h>
#include <unwind.h>

Q_IMPORT_PLUGIN(DeskDroidIntegrationPlugin)

namespace {

// Counts frames and prints the rate every 5 s (the app's log goes to DeskDroid's).
struct FpsCounter {
    QElapsedTimer clock, window;
    int frames = 0;
    double fps = 0;
    void tick(const char *name)
    {
        if (!clock.isValid()) { clock.start(); window.start(); }
        frames++;
        if (window.elapsed() >= 1000) {
            fps = frames * 1000.0 / window.elapsed();
            frames = 0;
            window.restart();
            static int n;
            if (++n % 5 == 0) printf("%s: %.0f fps\n", name, fps);
        }
    }
};

void paintScene(QPainter &p, QSize size, double t, QPointF pointer, const QString &title,
                double fps, const QString &extra)
{
    QLinearGradient bg(0, 0, 0, size.height());
    bg.setColorAt(0, QColor(28, 30, 58));
    bg.setColorAt(1, QColor(52, 24, 70));
    p.fillRect(QRect(QPoint(), size), bg);
    p.setRenderHint(QPainter::Antialiasing);

    const QPointF c(size.width() * 0.72, size.height() * 0.58);
    for (int i = 0; i < 12; i++) {
        p.save();
        p.translate(c);
        p.rotate(t * 40 + i * 30);
        p.setBrush(QColor::fromHsvF(std::fmod(i / 12.0 + t * 0.05, 1.0), 0.7, 1.0, 0.85));
        p.setPen(Qt::NoPen);
        p.drawRoundedRect(QRectF(40, -14, 90, 28), 14, 14);
        p.restore();
    }

    p.setPen(Qt::white);
    QFont f = p.font();
    f.setPixelSize(30);
    f.setBold(true);
    p.setFont(f);
    p.drawText(QPointF(24, 52), title);
    f.setPixelSize(20);
    f.setBold(false);
    p.setFont(f);
    p.drawText(QPointF(24, 88), QStringLiteral("%1 fps · Qt %2 on the phone's own driver").arg(qRound(fps)).arg(QT_VERSION_STR));
    p.drawText(QRectF(24, 104, size.width() * 0.45, size.height() - 120), Qt::TextWordWrap, extra);

    p.setBrush(QColor(255, 255, 255, 200));
    p.setPen(Qt::NoPen);
    p.drawEllipse(pointer, 12, 12);
}

class RasterDemo : public QRasterWindow
{
public:
    RasterDemo() { setTitle(QStringLiteral("Qt raster")); }

protected:
    void paintEvent(QPaintEvent *) override
    {
        m_fps.tick("Qt raster");
        QPainter p(this);
        paintScene(p, size(), m_fps.clock.isValid() ? m_fps.clock.elapsed() / 1000.0 : 0, m_pointer,
                   QStringLiteral("Qt raster window"), m_fps.fps,
                   QStringLiteral("Software QPainter, like Qt Widgets. Type here: ") + m_text +
                       QStringLiteral("_"));
        update(); // the compositor's frame event paces this
    }
    void mouseMoveEvent(QMouseEvent *e) override { m_pointer = e->position(); }
    void mousePressEvent(QMouseEvent *e) override { m_pointer = e->position(); }
    void keyPressEvent(QKeyEvent *e) override
    {
        if (e->key() == Qt::Key_Backspace) m_text.chop(1);
        else m_text += e->text();
    }

private:
    FpsCounter m_fps;
    QPointF m_pointer { -100, -100 };
    QString m_text;
};

class GLDemo : public QOpenGLWindow
{
public:
    GLDemo() { setTitle(QStringLiteral("Qt OpenGL")); }

protected:
    void paintGL() override
    {
        m_fps.tick("Qt OpenGL");
        QPainter p(this);
        paintScene(p, size(), m_fps.clock.isValid() ? m_fps.clock.elapsed() / 1000.0 : 0, m_pointer,
                   QStringLiteral("Qt OpenGL window"), m_fps.fps,
                   QStringLiteral("QPainter on the GPU, the path Qt Quick and Plasma use. GL: ") +
                       QString::fromLatin1(reinterpret_cast<const char *>(context()->functions()->glGetString(GL_RENDERER))));
        p.end();
        update();
    }
    void mouseMoveEvent(QMouseEvent *e) override { m_pointer = e->position(); }
    void mousePressEvent(QMouseEvent *e) override { m_pointer = e->position(); }

private:
    FpsCounter m_fps;
    QPointF m_pointer { -100, -100 };
};

// Qt for Android logs to logcat; send it to stderr, which DeskDroid shows and logs.
void logToStderr(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
    static const char *const kinds[] = { "debug", "warning", "critical", "fatal", "info" };
    fprintf(stderr, "qt %s: %s\n", type <= QtInfoMsg ? kinds[type] : "?", qPrintable(msg));
}

_Unwind_Reason_Code printFrame(_Unwind_Context *ctx, void *depth)
{
    uintptr_t pc = _Unwind_GetIP(ctx);
    if (!pc || ++*static_cast<int *>(depth) > 24) return _URC_END_OF_STACK;
    Dl_info info = {};
    dladdr(reinterpret_cast<void *>(pc), &info);
    const char *lib = info.dli_fname ? strrchr(info.dli_fname, '/') : nullptr;
    char line[256];
    int n = snprintf(line, sizeof line, "  at %s+0x%lx %s\n", lib ? lib + 1 : "?",
                     static_cast<unsigned long>(pc - reinterpret_cast<uintptr_t>(info.dli_fbase)),
                     info.dli_sname ? info.dli_sname : "");
    write(STDERR_FILENO, line, n);
    return _URC_NO_REASON;
}

// Prints where it crashed (library, offset, symbol), then crashes as before.
void onCrash(int sig)
{
    char line[64];
    int n = snprintf(line, sizeof line, "crashed with signal %d\n", sig);
    write(STDERR_FILENO, line, n);
    int depth = 0;
    _Unwind_Backtrace(printFrame, &depth);
    signal(sig, SIG_DFL);
    raise(sig);
}

} // namespace

int demoMain(int argc, char **argv)
{
    setvbuf(stdout, nullptr, _IOLBF, 0);
    setvbuf(stderr, nullptr, _IOLBF, 0);
    for (int sig : { SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE }) signal(sig, onCrash);
    qInstallMessageHandler(logToStderr);
    printf("starting Qt %s\n", qVersion());
    QSurfaceFormat fmt;
    fmt.setRenderableType(QSurfaceFormat::OpenGLES);
    fmt.setVersion(3, 0);
    fmt.setDepthBufferSize(24);
    fmt.setStencilBufferSize(8);
    QSurfaceFormat::setDefaultFormat(fmt);

    // Without an Android Context Qt can't look these up: startup asks Android
    // for the app version unless one is set, and the shader disk cache asks
    // for the cache folder.
    QCoreApplication::setApplicationVersion(QStringLiteral("1"));
    QCoreApplication::setAttribute(Qt::AA_DisableShaderDiskCache);

    QGuiApplication app(argc, argv);
    printf("Qt %s started on platform %s\n", qVersion(), qPrintable(QGuiApplication::platformName()));
    QFont font(QStringLiteral("Roboto"));
    QGuiApplication::setFont(font);

    RasterDemo raster;
    raster.resize(760, 440);
    raster.show();
    GLDemo gl;
    gl.resize(760, 440);
    gl.show();
    return app.exec();
}

// QtHost.run(String[] args): runs the demo on the calling (Java main) thread.
extern "C" JNIEXPORT jint JNICALL Java_io_deskdroid_app_QtHost_run(JNIEnv *env, jclass, jobjectArray jargs)
{
    static std::vector<std::string> args; // Qt keeps argv for the app's lifetime
    static std::vector<char *> argv;
    args.push_back("nativedesk_qt");
    for (jsize i = 0, n = env->GetArrayLength(jargs); i < n; i++) {
        auto js = static_cast<jstring>(env->GetObjectArrayElement(jargs, i));
        const char *c = env->GetStringUTFChars(js, nullptr);
        args.emplace_back(c);
        env->ReleaseStringUTFChars(js, c);
    }
    for (auto &a : args) argv.push_back(a.data());
    argv.push_back(nullptr);
    return demoMain(int(args.size()), argv.data());
}
