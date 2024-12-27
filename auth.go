package gcf

import (
	"context"
	"fmt"

	credentials "cloud.google.com/go/iam/credentials/apiv1"
	credentialspb "cloud.google.com/go/iam/credentials/apiv1/credentialspb"
	"google.golang.org/api/option"
)

// generateAccessToken generates an access token for the target service account
func generateAccessToken(ctx context.Context, targetServiceAccount string) (string, error) {
	// Create an IAM Credentials client
	iamClient, err := credentials.NewIamCredentialsClient(ctx, option.WithScopes("https://www.googleapis.com/auth/cloud-platform"))
	if err != nil {
		return "", fmt.Errorf("failed to create IAM Credentials client: %v", err)
	}
	defer iamClient.Close()

	// Build the request
	req := &credentialspb.GenerateAccessTokenRequest{
		Name:  fmt.Sprintf("projects/-/serviceAccounts/%s", targetServiceAccount),
		Scope: []string{"https://www.googleapis.com/auth/cloud-platform"},
	}

	// Call the GenerateAccessToken method
	resp, err := iamClient.GenerateAccessToken(ctx, req)
	if err != nil {
		return "", fmt.Errorf("failed to generate access token: %v", err)
	}

	return resp.AccessToken, nil
}
