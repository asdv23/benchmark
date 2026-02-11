package runner

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestEnsureMantleChainConfig(t *testing.T) {
	dir := t.TempDir()
	chainCfgPath := filepath.Join(dir, "chain.json")

	// Write minimal chain.json without Mantle fields (simulates go-ethereum Encode output)
	root := map[string]interface{}{
		"config": map[string]interface{}{
			"chainId": 1337,
			"shanghaiTime": 0,
		},
		"nonce": "0x0",
		"timestamp": "0x0",
	}
	data, err := json.Marshal(root)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(chainCfgPath, data, 0644); err != nil {
		t.Fatal(err)
	}

	if err := ensureMantleChainConfig(chainCfgPath); err != nil {
		t.Fatal(err)
	}

	// Verify Mantle fields were added
	data, err = os.ReadFile(chainCfgPath)
	if err != nil {
		t.Fatal(err)
	}
	var out map[string]interface{}
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatal(err)
	}
	config, _ := out["config"].(map[string]interface{})
	if config == nil {
		t.Fatal("config missing")
	}
	for _, key := range []string{"mantleEverestTime", "mantleSkadiTime", "mantleLimbTime", "mantleArsiaTime"} {
		v, has := config[key]
		if !has {
			t.Errorf("config missing %s", key)
			continue
		}
		if n, ok := v.(float64); !ok || n != 0 {
			t.Errorf("config[%s] = %v (want 0)", key, v)
		}
	}
}
