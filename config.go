package gcf

// Config holds environment variables for the function
type Config struct {
	TargetBucket         string
	TargetServiceAccount string
}

func NewConfig() *Config {
	return &Config{
		TargetBucket:         "your-target-bucket-name",                                          // Replace with your bucket name
		TargetServiceAccount: "your-target-service-account@your-project.iam.gserviceaccount.com", // Replace with your service account email
	}
}
