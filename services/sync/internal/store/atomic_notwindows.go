//go:build !windows

package store

import (
	"errors"
	"os"
	"syscall"
)

func replaceFile(source, destination string) error {
	return os.Rename(source, destination)
}

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return err
	}
	defer directory.Close()
	if err := directory.Sync(); err != nil {
		// Some non-Linux filesystems explicitly do not implement directory
		// fsync. All other errors must reach the caller.
		if errors.Is(err, syscall.EINVAL) || errors.Is(err, syscall.ENOTSUP) {
			return nil
		}
		return err
	}
	return nil
}
