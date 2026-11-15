/*
 * fork() + execv() 启动内核子进程，并把已有 fd（TUN）原样继承过去。
 *
 * 为什么不用 Java 的 ProcessBuilder：Android 的进程创建走 posix_spawn 并带
 * POSIX_SPAWN_CLOEXEC_DEFAULT，会把父进程除了 stdio 之外的所有 fd 关掉。
 * 即使我们清了 FD_CLOEXEC，子进程里那个 TUN fd 依然是关闭的 —— 实测内核报
 *   Start TUN listening error: unix.SetNonblock(162) failed: bad file descriptor
 * 所以这里必须自己 fork：fork 出来的子进程继承完整 fd 表，exec 时只关闭带
 * FD_CLOEXEC 的 fd（我们事先清过），TUN 的 fd 号在父子进程里完全一致，运行
 * 配置里写的 file-descriptor 不需要换算。
 *
 * 子进程在 exec 之前只调用 async-signal-safe 的函数（chdir/dup2/open/execv/
 * _exit），不碰 malloc，也不会回到 Dart/ART 运行时。
 */
#include <jni.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

/* 把 stdout/stderr 都重定向到日志文件，Android 应用的 stdout 本来也是丢弃的。 */
static int redirect_log(const char *path) {
    if (path == NULL) return -1;
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) return -1;
    dup2(fd, STDOUT_FILENO);
    dup2(fd, STDERR_FILENO);
    if (fd > STDERR_FILENO) close(fd);
    return 0;
}

JNIEXPORT jint JNICALL
Java_dev_clashdeck_NativeSpawn_spawn(JNIEnv *env, jobject thiz, jstring jbinary,
                                     jobjectArray jargv, jint tunFd,
                                     jstring jlogPath, jstring jworkDir) {
    (void) thiz;
    if (jbinary == NULL || jargv == NULL) return -EINVAL;

    const char *binary = (*env)->GetStringUTFChars(env, jbinary, NULL);
    if (binary == NULL) return -ENOMEM;

    jsize argc = (*env)->GetArrayLength(env, jargv);
    if (argc <= 0) {
        (*env)->ReleaseStringUTFChars(env, jbinary, binary);
        return -EINVAL;
    }

    /* fork 会连堆一起复制，所以这些内存在子进程里同样可读。 */
    char **argv = (char **) calloc((size_t) argc + 1, sizeof(char *));
    if (argv == NULL) {
        (*env)->ReleaseStringUTFChars(env, jbinary, binary);
        return -ENOMEM;
    }
    for (jsize i = 0; i < argc; i++) {
        jstring item = (jstring) (*env)->GetObjectArrayElement(env, jargv, i);
        argv[i] = item == NULL ? (char *) "" : (char *) (*env)->GetStringUTFChars(env, item, NULL);
    }
    argv[argc] = NULL;

    const char *logPath = jlogPath == NULL ? NULL : (*env)->GetStringUTFChars(env, jlogPath, NULL);
    const char *workDir = jworkDir == NULL ? NULL : (*env)->GetStringUTFChars(env, jworkDir, NULL);

    pid_t pid = fork();
    if (pid < 0) {
        int err = errno;
        (*env)->ReleaseStringUTFChars(env, jbinary, binary);
        return -err;
    }

    if (pid == 0) {
        /* ---------- 子进程：只做 async-signal-safe 的事 ---------- */
        if (workDir != NULL) {
            (void) chdir(workDir);
        }
        if (tunFd >= 0) {
            /* fork 已经让它继承过来了，这里再保险一次：不要带 FD_CLOEXEC。 */
            int flags = fcntl(tunFd, F_GETFD);
            if (flags >= 0) (void) fcntl(tunFd, F_SETFD, flags & ~FD_CLOEXEC);
        }
        (void) redirect_log(logPath);
        execv(binary, argv);
        _exit(127);
    }

    /* ---------- 父进程 ---------- */
    (*env)->ReleaseStringUTFChars(env, jbinary, binary);
    for (jsize i = 0; i < argc; i++) {
        jstring item = (jstring) (*env)->GetObjectArrayElement(env, jargv, i);
        if (item != NULL) {
            (*env)->ReleaseStringUTFChars(env, item, argv[i]);
        }
    }
    free(argv);
    if (logPath != NULL) (*env)->ReleaseStringUTFChars(env, jlogPath, logPath);
    if (workDir != NULL) (*env)->ReleaseStringUTFChars(env, jworkDir, workDir);

    return (jint) pid;
}

/* 阻塞回收子进程，返回退出码（被信号杀死时为 128+signal）。 */
JNIEXPORT jint JNICALL
Java_dev_clashdeck_NativeSpawn_waitPid(JNIEnv *env, jobject thiz, jint pid) {
    (void) env;
    (void) thiz;
    int status = 0;
    pid_t result;
    do {
        result = waitpid((pid_t) pid, &status, 0);
    } while (result < 0 && errno == EINTR);
    if (result < 0) return -errno;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return -1;
}

/* 打信号（SIGTERM/SIGKILL），返回 0 表示成功。 */
JNIEXPORT jint JNICALL
Java_dev_clashdeck_NativeSpawn_sendSignal(JNIEnv *env, jobject thiz, jint pid, jint signal) {
    (void) env;
    (void) thiz;
    if (kill((pid_t) pid, signal) != 0) return -errno;
    return 0;
}
