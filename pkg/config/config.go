package config

type Config struct {
	Stride  int
	Overlap int
}

func NewConfig() Config {
	return Config{
		Stride:  500,
		Overlap: 50,
	}
}
