package gcf

import (
	"context"
	"fmt"

	credentials "cloud.google.com/go/iam/credentials/apiv1"
	credentialspb "cloud.google.com/go/iam/credentials/apiv1/credentialspb"
)

// createCredentialsClient creates a new IAM credentials client
func createCredentialsClient(ctx context.Context) (*credentials.IamCredentialsClient, error) {
	return credentials.NewIamCredentialsClient(ctx)
}

// generateAccessToken generates an access token for the target service account
func generateAccessToken(ctx context.Context, client *credentials.IamCredentialsClient, cfg *Config) (string, error) {
	tokenRequest := &credentialspb.GenerateAccessTokenRequest{
		Name: fmt.Sprintf(cfg.ServiceAccountFormat, cfg.TargetServiceAccount),
		Scope: []string{
			cfg.StorageScope,
		},
	}
	tokenResponse, err := client.GenerateAccessToken(ctx, tokenRequest)
	if err != nil {
		return "", err
	}
	return tokenResponse.AccessToken, nil
}
