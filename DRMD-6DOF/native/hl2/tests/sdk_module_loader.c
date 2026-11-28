#include <dlfcn.h>
#include <stdio.h>

typedef void *(*InterfaceFactory)(const char *, int *);

int main(int argc, char **argv) {
    if (argc != 3) return 64;
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "dlopen: %s\n", dlerror());
        return 1;
    }
    InterfaceFactory get = (InterfaceFactory)dlsym(handle, "CreateInterface");
    if (!get) {
        fprintf(stderr, "dlsym: %s\n", dlerror());
        return 2;
    }
    int status = -1;
    void *api = get(argv[2], &status);
    if (!api || status != 0) {
        fprintf(stderr, "CreateInterface(%s): %d\n", argv[2], status);
        return 3;
    }
    printf("PASS | ELF32 load and CreateInterface(%s)\n", argv[2]);
    return 0;
}
