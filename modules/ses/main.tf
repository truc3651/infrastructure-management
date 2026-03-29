resource "aws_ses_template" "welcome_mail" {
  name    = "welcome-mail-${var.environment}"
  subject = "Welcome to our platform!"

  html = <<-EOT
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Welcome, {{username}}!</h1>
        <p>Thank you for joining our platform. Your account has been successfully created.</p>
        <p>You can now log in and start using our services.</p>
      </body>
    </html>
  EOT

  text = "Welcome, {{username}}! Your account has been successfully created. You can now log in and start using our services."
}

resource "aws_ses_template" "forgot_password_mail" {
  name    = "forgot-password-mail-${var.environment}"
  subject = "Reset your password"

  html = <<-EOT
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Password Reset Request</h1>
        <p>We received a request to reset your password.</p>
        <p>Click the link below to reset your password:</p>
        <p><a href="https://{{domain}}/reset-password?token={{token}}">Reset Password</a></p>
        <p>If you did not request a password reset, please ignore this email.</p>
        <p>This link will expire in 24 hours.</p>
      </body>
    </html>
  EOT

  text = "We received a request to reset your password. Visit https://{{domain}}/reset-password?token={{token}} to reset your password. If you did not request a password reset, please ignore this email. This link will expire in 24 hours."
}
