package main

import (
	"flag"
	"fmt"
	"io"
	"net"
	"syscall"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"golang.org/x/sys/unix"
)

const socketProtectionTimeout = 3 * time.Second

// Register before the upstream main package parses flags in init.
var _ = registerClashDeckSocketProtection()

func registerClashDeckSocketProtection() struct{} {
	flag.Func("clashdeck-protect-socket", "Android VPN socket protection endpoint", func(name string) error {
		if name == "" {
			return fmt.Errorf("empty VPN socket protection endpoint")
		}
		dialer.DefaultSocketHook = func(_, _ string, raw syscall.RawConn) error {
			var err error
			if controlErr := raw.Control(func(fd uintptr) { err = requestSocketProtection(name, fd) }); controlErr != nil {
				return controlErr
			}
			if err != nil {
				return fmt.Errorf("Android VPN protect socket: %w", err)
			}
			return nil
		}
		return nil
	})
	return struct{}{}
}

func requestSocketProtection(name string, fd uintptr) error {
	connection, err := net.DialTimeout("unix", "@"+name, socketProtectionTimeout)
	if err != nil {
		return err
	}
	defer connection.Close()
	channel := connection.(*net.UnixConn)
	if err = channel.SetDeadline(time.Now().Add(socketProtectionTimeout)); err != nil {
		return err
	}
	if _, _, err = channel.WriteMsgUnix([]byte{1}, unix.UnixRights(int(fd)), nil); err != nil {
		return err
	}
	var reply [1]byte
	if _, err = io.ReadFull(channel, reply[:]); err != nil {
		return err
	}
	if reply[0] != 1 {
		return fmt.Errorf("VPN service rejected socket protection")
	}
	return nil
}
