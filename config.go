package gcf

// Config holds the configuration for the Google Cloud Function
type Config struct {
	SourceProjectID      string
	SourceFunctionRegion string
	SourceFunctionName   string
	TargetProjectID      string
	TargetBucketName     string
	TargetServiceAccount string
	StorageScope         string
	ServiceAccountFormat string
}

// NewConfig creates a new config with default values
func NewConfig() *Config {
	return &Config{
		SourceProjectID:      "proj-awoosnam",
		SourceFunctionRegion: "us-central1",
		SourceFunctionName:   "my-func",
		TargetProjectID:      "striped-device-445917-b7",
		TargetBucketName:     "my-super-cool-bucket",
		TargetServiceAccount: "bucket-reader@striped-device-445917-b7.iam.gserviceaccount.com",
		StorageScope:         "https://www.googleapis.com/auth/cloud-platform",
		ServiceAccountFormat: "projects/-/serviceAccounts/%s",
	}
}
