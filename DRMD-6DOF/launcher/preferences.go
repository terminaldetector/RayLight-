package main

import "encoding/json"

type targetPreferences struct {
	MapIndex        int  `json:"map_index"`
	GraphicsIndex   int  `json:"graphics_index"`
	ResolutionIndex int  `json:"resolution_index"`
	Windowed        bool `json:"windowed"`
	Console         bool `json:"console"`
}

type preferences struct {
	Target        Target                       `json:"target"`
	GModPath      string                       `json:"gmod_path"`
	HL2Path       string                       `json:"hl2_path"`
	SDKPath       string                       `json:"sdk_path,omitempty"`
	NativeModPath string                       `json:"native_mod_path,omitempty"`
	Profiles      map[Target]targetPreferences `json:"profiles"`
	targetPreferences
}

func defaultPreferences() preferences {
	return preferences{
		Target: TargetGMod,
		Profiles: map[Target]targetPreferences{
			TargetGMod:      {MapIndex: 3, Windowed: true},
			TargetHL2:       {MapIndex: 1, Windowed: true},
			TargetHL2Native: {MapIndex: 1, Windowed: true},
		},
		targetPreferences: targetPreferences{MapIndex: 3, Windowed: true},
	}
}

func decodePreferences(data []byte) preferences {
	defaults := defaultPreferences()
	saved := preferences{Target: defaults.Target, targetPreferences: defaults.targetPreferences}
	if err := json.Unmarshal(data, &saved); err != nil {
		return defaults
	}
	if _, valid := defaults.Profiles[saved.Target]; !valid {
		saved.Target = TargetGMod
	}
	if len(saved.Profiles) == 0 {
		defaults.Profiles[saved.Target] = saved.targetPreferences
	}
	for target, options := range saved.Profiles {
		if _, valid := defaults.Profiles[target]; valid {
			defaults.Profiles[target] = options
		}
	}
	saved.Profiles = defaults.Profiles
	return saved
}
