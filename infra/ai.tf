resource "aws_iam_role" "parser" {
  name               = "demo-meetings-ai-ParserRole-0JIjo3nGzlco"
  assume_role_policy = local.lambda_assume_role
  tags               = { Project = var.project_name }
}

resource "aws_iam_role_policy_attachment" "parser_basic" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "parser_bedrock" {
  name = "bedrock-invoke"
  role = aws_iam_role.parser.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "parser" {
  function_name = "demo-meetings-ai-ParserFunction-MPderRFP2aWI"
  package_type  = "Image"
  image_uri     = var.parser_image_uri
  architectures = ["arm64"]
  role          = aws_iam_role.parser.arn
  timeout       = 30
  memory_size   = 512
  tags          = { Project = var.project_name }

  image_config {
    entry_point = ["python", "-m", "awslambdaric"]
    command     = ["app.ai.agenda_lambda.handler"]
  }

  environment {
    variables = {
      PARSER_MODEL         = var.parser_model
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_REGION       = var.region
    }
  }

  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = [var.site_origin]
    allow_methods = ["POST"]
    allow_headers = ["content-type", "authorization"]
  }
}

resource "aws_lambda_permission" "parser_url" {
  statement_id           = "demo-meetings-ai-ParserUrlPermission-CFQYT5v0GeHr"
  function_name          = aws_lambda_function.parser.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_invoke" {
  statement_id             = "demo-meetings-ai-ParserUrlInvokePermission-CF237keJX546"
  function_name            = aws_lambda_function.parser.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}
