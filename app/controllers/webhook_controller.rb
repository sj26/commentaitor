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

        sagemaker_response = sagemaker_client.invoke_endpoint({
          endpoint_name: sagemaker_text_endpoint_name,
          content_type: "application/json",
          accept: "application/json",
          body: {
            "inputs" => <<~PROMPT,
              You are an expert programmer, and you are writing a comment on a new pull request.

              THE PULL REQUEST TITLE IS:
              #{pull_request_title}

              THE PULL REQUEST BODY IS:
              #{pull_request_body}

              THE PULL REQUEST COMMENT IS:
            PROMPT
            "parameters" => {
              "do_sample" => true,
              "top_p" => 0.9,
              "temperature" => 0.8,
              "max_new_tokens" => 1024,
              "stop" => ["<|endoftext|>", "</s>"],
            }
          }.to_json,
        })
        sagemaker_body = ActiveSupport::JSON.decode(sagemaker_response.body.read)
        sagemaker_comment = sagemaker_body[0]["generated_text"]

        Jets.logger.info "Sagemaker response:\n#{sagemaker_body.pretty_inspect}"

        github_installation_id = params.fetch("installation").fetch("id")
        github_installation_access_token = github_app_client.create_installation_access_token(github_installation_id)
        github_installation_client = Octokit::Client.new(bearer_token: github_installation_access_token.fetch(:token))

        github_comment = github_installation_client.add_comment(repository_id, pull_request_number, sagemaker_comment)

        Jets.logger.info "GitHub comment:\n#{github_comment.pretty_inspect}"
      end
    end

    render json: {}
  end

  private

  def sagemaker_text_endpoint_name
    ENV.fetch("SAGEMAKER_TEXT_ENDPOINT_NAME")
  end

  def sagemaker_client
    @sagemaker_client ||= Aws::SageMakerRuntime::Client.new
  end

  def github_event
    # jets downcases all header names
    request.headers.fetch("x-github-event")
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
