package core

import (
	"syscall"
	"unsafe"
)

// Steam registers the active user install as well as the machine-wide location.
func steamRegistryPaths() []string {
	var paths []string
	for _, entry := range []struct {
		hive syscall.Handle
		key  string
		name string
	}{
		{syscall.HKEY_CURRENT_USER, `Software\Valve\Steam`, "SteamExe"},
		{syscall.HKEY_CURRENT_USER, `Software\Valve\Steam`, "SteamPath"},
		{syscall.HKEY_LOCAL_MACHINE, `Software\WOW6432Node\Valve\Steam`, "InstallPath"},
		{syscall.HKEY_LOCAL_MACHINE, `Software\Valve\Steam`, "InstallPath"},
	} {
		path, _ := syscall.UTF16PtrFromString(entry.key)
		name, _ := syscall.UTF16PtrFromString(entry.name)
		var key syscall.Handle
		if syscall.RegOpenKeyEx(entry.hive, path, 0, syscall.KEY_QUERY_VALUE, &key) != nil {
			continue
		}
		buffer := make([]uint16, 32768)
		size := uint32(len(buffer) * 2)
		var kind uint32
		err := syscall.RegQueryValueEx(key, name, nil, &kind, (*byte)(unsafe.Pointer(&buffer[0])), &size)
		syscall.RegCloseKey(key)
		if err == nil && (kind == syscall.REG_SZ || kind == syscall.REG_EXPAND_SZ) {
			paths = append(paths, syscall.UTF16ToString(buffer[:size/2]))
		}
	}
	return paths
}
