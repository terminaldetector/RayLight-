package core

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

func lockInstall(work string) (func(), error) {
	if err := os.MkdirAll(work, 0o755); err != nil {
		return nil, err
	}
	path, err := syscall.UTF16PtrFromString(filepath.Join(work, "operation.lock"))
	if err != nil {
		return nil, err
	}
	handle, err := syscall.CreateFile(path, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil,
		syscall.OPEN_ALWAYS, syscall.FILE_ATTRIBUTE_NORMAL, 0)
	if err != nil {
		return nil, fmt.Errorf("Папка пакетов занята или недоступна: %w", err)
	}
	return func() { _ = syscall.CloseHandle(handle) }, nil
}
