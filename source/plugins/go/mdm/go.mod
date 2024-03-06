module Docker-Provider/source/plugins/go/src/mdm

go 1.19

require (
	github.com/fluent/fluent-bit-go v0.0.0-20230731091245-a7a013e2473c
	github.com/google/uuid v1.5.0
	gopkg.in/natefinch/lumberjack.v2 v2.2.1
	Docker-Provider/source/plugins/go/input v0.0.0
)

require github.com/ugorji/go/codec v1.1.7 // indirect

replace Docker-Provider/source/plugins/go/input => ../input
