package core

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

type LaunchPlan struct {
	Executable string
	Args       []string
	listenPath string
	listenMode string
}

var mapName = regexp.MustCompile(`^[A-Za-z0-9_][A-Za-z0-9_/\-]{0,111}$`)

func BuildLaunch(cfg Config, profile Profile) (LaunchPlan, error) {
	var options Options
	switch profile {
	case GMod:
		options = cfg.GMod
	case HL2:
		options = cfg.HL2
	case HL2Content:
		options = cfg.HL2Content
	default:
		return LaunchPlan{}, fmt.Errorf("Неизвестный профиль запуска: %q", profile)
	}
	if err := validOptions(options, profile); err != nil {
		return LaunchPlan{}, err
	}
	found := Detect(cfg)
	plan := LaunchPlan{Executable: found.SteamPath}
	switch profile {
	case GMod:
		if !found.GMod.Ready {
			return LaunchPlan{}, fmt.Errorf("%s", found.GMod.Message)
		}
		plan.Args = []string{"-applaunch", "4000"}
	case HL2:
		if !found.HL2.Ready {
			return LaunchPlan{}, fmt.Errorf("%s", found.HL2.Message)
		}
		plan.Args = []string{"-applaunch", "243730", "-game", found.NativePath}
	case HL2Content:
		if !found.HL2Content.Ready {
			return LaunchPlan{}, errors.New(found.HL2Content.Message)
		}
		plan.Args = []string{"-applaunch", "220"}
	}
	if options.Map != "" && strings.HasPrefix(strings.ToLower(options.Map), "d6_") {
		if err := requireAbaddonMap(profile, found, options.Map); err != nil {
			return LaunchPlan{}, err
		}
	}
	switch options.Display {
	case "fullscreen":
		plan.Args = append(plan.Args, "-fullscreen")
	case "borderless":
		plan.Args = append(plan.Args, "-windowed", "-noborder")
	default:
		plan.Args = append(plan.Args, "-windowed")
	}
	if options.Width != 0 {
		plan.Args = append(plan.Args, "-w", strconv.Itoa(options.Width), "-h", strconv.Itoa(options.Height))
	}
	if options.Console {
		plan.Args = append(plan.Args, "-console")
	}
	if options.SkipIntro {
		plan.Args = append(plan.Args, "-novid")
	}
	if options.DebugLog {
		plan.Args = append(plan.Args, "-condebug")
	}
	if profile == GMod {
		gameProfile := options.GameProfile
		if gameProfile == "" {
			gameProfile = "auto"
		}
		filename := "abaddon_launcher_" + gameProfile + ".cfg"
		plan.listenPath = filepath.Join(found.GModPath, "garrysmod", "cfg", filename)
		plan.listenMode = gameProfile
		plan.Args = append(plan.Args, "+gamemode", "sandbox", "+lservercfgfile", filename)
	}
	if options.Map != "" {
		plan.Args = append(plan.Args, "+map", options.Map)
	}
	return plan, nil
}

func validOptions(options Options, profile Profile) error {
	if options.Map != "" && !mapName.MatchString(options.Map) {
		return fmt.Errorf("Имя карты может содержать латиницу, цифры, дефис, подчёркивание и /.")
	}
	if options.Width != 0 || options.Height != 0 {
		if options.Width < 640 || options.Width > 7680 || options.Height < 480 || options.Height > 4320 {
			return fmt.Errorf("Укажите ширину от 640 до 7680 и высоту от 480 до 4320. Два нуля оставляют настройки игры.")
		}
	}
	switch options.Display {
	case "windowed", "fullscreen", "borderless":
	default:
		return fmt.Errorf("Выберите оконный, полноэкранный или безрамочный режим.")
	}
	if profile == GMod {
		switch options.GameProfile {
		case "", "auto", "campaign", "arena":
		default:
			return fmt.Errorf("Неизвестный режим Abaddon для Garry’s Mod: %q", options.GameProfile)
		}
	}
	return nil
}

func requireAbaddonMap(profile Profile, found Detection, name string) error {
	mapPath := filepath.FromSlash(name + ".bsp")
	var folders []string
	switch profile {
	case HL2:
		folders = []string{filepath.Join(found.NativePath, "maps"), filepath.Join(found.SDKPath, "hl2", "maps")}
	case HL2Content:
		folders = []string{filepath.Join(contentPayload(found.ContentPath), "maps"), filepath.Join(found.ContentPath, "hl2", "maps")}
	default:
		folders = []string{filepath.Join(gmodContent(found.GModPath), "maps"), filepath.Join(found.GModPath, "garrysmod", "maps")}
	}
	for _, folder := range folders {
		if isFile(filepath.Join(folder, mapPath)) {
			return nil
		}
	}
	return fmt.Errorf("Карта %s.bsp не найдена в установленном Abaddon.", name)
}

func (plan LaunchPlan) Start() error {
	if err := plan.prepareListenConfig(); err != nil {
		return fmt.Errorf("Не удалось настроить локальную игру Garry’s Mod: %w", err)
	}
	command := exec.Command(plan.Executable, plan.Args...)
	command.Dir = filepath.Dir(plan.Executable)
	if err := command.Start(); err != nil {
		return fmt.Errorf("Не удалось передать запуск Steam: %w", err)
	}
	return command.Process.Release()
}

func (plan LaunchPlan) prepareListenConfig() error {
	if plan.listenPath == "" {
		return nil
	}
	// The engine executes the listen-server config after the add-on registers its ConVars.
	contents := "// Half-Life: Abaddon Launcher\nexec listenserver.cfg\nd6_profile " + plan.listenMode + "\n"
	if err := os.MkdirAll(filepath.Dir(plan.listenPath), 0o755); err != nil {
		return err
	}
	config, err := os.OpenFile(plan.listenPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if errors.Is(err, os.ErrExist) {
		previous, readErr := os.ReadFile(plan.listenPath)
		if readErr != nil {
			return readErr
		}
		if string(previous) != contents {
			return fmt.Errorf("Файл %s занят другим конфигом", plan.listenPath)
		}
		return nil
	}
	if err != nil {
		return err
	}
	_, err = config.WriteString(contents)
	closeErr := config.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		_ = os.Remove(plan.listenPath)
	}
	return err
}
