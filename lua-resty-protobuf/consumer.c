#include <stdio.h>
#include <sys/uio.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdlib.h>


#define LISTEN_ADDRESS "127.0.0.1"
#define LISTEN_PORT 9999

// fork 4 worker processes to read and discard the incoming UDP packets
int main() {
    int listen_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (listen_fd < 0) {
        perror("socket");
        return 1;
    }

    // set infinite timeout
    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 0;
    if (setsockopt(listen_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
        perror("setsockopt");
        return 1;
    }

    struct sockaddr_in listen_addr;
    listen_addr.sin_family = AF_INET;
    listen_addr.sin_port = htons(LISTEN_PORT);
    listen_addr.sin_addr.s_addr = inet_addr(LISTEN_ADDRESS);
    if (bind(listen_fd, (struct sockaddr *)&listen_addr, sizeof(listen_addr)) < 0) {
        perror("bind");
        return 1;
    }

    for (int i = 0; i < 2; i++) {
        pid_t pid = fork();
        if (pid < 0) {
            perror("fork");
            return 1;
        }
        if (pid == 0) {
            char* buf = malloc(1024 * 1024); // 1MB
            ssize_t total = 0;
            while (1) {
                ssize_t n = read(listen_fd, buf, 1024 * 1024);
                if (n < 0) {
                    perror("read");
                    return 1;
                }
            }
        }
    }

    for (int i = 0; i < 4; i++) {
        wait(NULL);
    }

    return 0;
}