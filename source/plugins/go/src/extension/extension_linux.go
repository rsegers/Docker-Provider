//go:build linux

package extension

func (e *Extension) GetOutputNamedPipe(datatype string) string {
	//unimplemented function
	logger.Printf("extensionconfig::GetOutputNamedPipe:: Function is not implemented for Linux")
	return ""
}

func getDataTypeToNamedPipeMapping() (map[string]string, error) {
	//unimplemented function
	logger.Printf("extensionconfig::getDataTypeToNamedPipeMapping:: Function is not implemented for Linux")
	return nil, nil

}
