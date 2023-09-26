module Docker-Provider/source/plugins/go/input

go 1.19

require github.com/calyptia/plugin v1.0.2

require (
	code.cloudfoundry.org/clock v1.1.0 // indirect
	github.com/Microsoft/go-winio v0.6.1 // indirect
	github.com/calyptia/cmetrics-go v0.1.7 // indirect
	github.com/docker/distribution v2.8.2+incompatible // indirect
	github.com/docker/go-connections v0.4.0 // indirect
	github.com/docker/go-units v0.5.0 // indirect
	github.com/gofrs/uuid v4.4.0+incompatible // indirect
	github.com/gogo/protobuf v1.3.2 // indirect
	github.com/google/uuid v1.3.1 // indirect
	github.com/morikuni/aec v1.0.0 // indirect
	github.com/opencontainers/go-digest v1.0.0 // indirect
	github.com/opencontainers/image-spec v1.0.2 // indirect
	github.com/pkg/errors v0.9.1 // indirect
	github.com/ugorji/go/codec v1.2.11 // indirect
	golang.org/x/mod v0.12.0 // indirect
	golang.org/x/net v0.15.0 // indirect
	golang.org/x/sys v0.12.0 // indirect
	golang.org/x/tools v0.13.0 // indirect
	gotest.tools/v3 v3.5.0 // indirect
)

require (
	Docker-Provider/source/plugins/go/src v0.0.0
	github.com/docker/docker v24.0.6+incompatible
	github.com/microsoft/ApplicationInsights-Go v0.4.4
	github.com/sirupsen/logrus v1.9.3
	gopkg.in/natefinch/lumberjack.v2 v2.2.1
)

replace Docker-Provider/source/plugins/go/src => ../src
