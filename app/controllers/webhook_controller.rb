class WebhookController < ApplicationController
  # https://rubyonjets.com/docs/iam-policies/
  iam_policy("sagemaker", {
    action: ["sagemaker:InvokeEndpoint"],
    effect: "Allow",
    resource: [
      "arn:aws:sagemaker:#{Jets.aws.region}:#{Jets.aws.account}:endpoint/*",
    ],
  })
  def process
    case github_event
    when "pull_request"
      case params[:action]
      when "opened"
        repository_id = params.fetch(:repository).fetch(:id)
        pull_request_number = params.fetch(:pull_request).fetch(:number)
        pull_request_title = params.fetch(:pull_request).fetch(:title)
        pull_request_body = params.fetch(:pull_request).fetch(:body)

        installation_id = params.fetch("installation").fetch("id")
        installation_access_token = github_app_client.create_installation_access_token(installation_id)
        installation_client = Octokit::Client.new(bearer_token: github_app_jwt)

        github_installation_client.add_comment(repository_id, pull_request_number, "Oh hello")
      end
    end

    render json: {}
  end

  private

  def github_event
    request.headers.fetch("X-GitHub-Event")
  end

  def github_installation_id
    request.headers.fetch("X-GitHub-Hook-Installation-Target-ID").to_i
  end

  def github_installation_client
    # https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation#authenticating-with-an-installation-access-token
    @github_installation_client ||= Octokit::Client.new(bearer_token: github_installation_access_token)
  end

  def github_installation_access_token
    # https://docs.github.com/en/rest/apps/apps#create-an-installation-access-token-for-an-app
    @github_installation_access_token ||= github_app_client.create_installation_access_token(github_installation_id).fetch(:token)
  end

  def github_app_client
    # https://github.com/octokit/octokit.rb#github-app
    @github_app_client ||= Octokit::Client.new(bearer_token: github_app_jwt)
  end

  def github_app_jwt
    # https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app
    JWT.encode({
      # issued at time, 60 seconds in the past to allow for clock drift
      iat: 60.seconds.ago.to_i,
      # JWT expiration time (10 minute maximum)
      exp: 10.minutes.from_now.to_i,
      # GitHub App's identifier
      iss: ENV.fetch("GITHUB_APP_ID"),
    }, github_app_private_key, "RS256")
  end

  def github_app_private_key
    OpenSSL::PKey::RSA.new(ENV.fetch("GITHUB_APP_PRIVATE_KEY"))
  end
end
