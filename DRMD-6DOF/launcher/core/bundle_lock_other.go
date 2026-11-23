//go:build !windows

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
	handle, err := os.OpenFile(filepath.Join(work, "operation.lock"), os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(handle.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		handle.Close()
		return nil, fmt.Errorf("Папка пакетов занята: %w", err)
	}
	return func() { _ = handle.Close() }, nil
}
