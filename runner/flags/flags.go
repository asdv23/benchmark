package flags

import (
	"github.com/urfave/cli/v2"

	opservice "github.com/ethereum-optimism/optimism/op-service"
)

const (
	RethBin         = "reth-bin"
	BuilderBin      = "builder-bin"
	GethBin         = "geth-bin"
	BaseRethNodeBin = "base-reth-node-bin"
	MantleCompat    = "mantle-compat"
)

func CLIFlags(envPrefix string) []cli.Flag {
	return []cli.Flag{
		&cli.StringFlag{
			Name:    RethBin,
			Usage:   "Reth binary path",
			Value:   "reth",
			EnvVars: opservice.PrefixEnvVar(envPrefix, "RETH_BIN"),
		},
		&cli.StringFlag{
			Name:    GethBin,
			Usage:   "Geth binary path",
			Value:   "geth",
			EnvVars: opservice.PrefixEnvVar(envPrefix, "GETH_BIN"),
		},
		&cli.StringFlag{
			Name:    BuilderBin,
			Usage:   "Builder binary path",
			Value:   "builder",
			EnvVars: opservice.PrefixEnvVar(envPrefix, "BUILDER_BIN"),
		},
		&cli.StringFlag{
			Name:    BaseRethNodeBin,
			Usage:   "Base Reth Node binary path",
			Value:   "base-reth-node",
			EnvVars: opservice.PrefixEnvVar(envPrefix, "BASE_RETH_NODE_BIN"),
		},
		&cli.BoolFlag{
			Name:    MantleCompat,
			Usage:   "Use Mantle-compatible DepositTx RLP (10 fields: adds EthValue, EthTxValue)",
			Value:   false,
			EnvVars: opservice.PrefixEnvVar(envPrefix, "MANTLE_COMPAT"),
		},
	}
}
