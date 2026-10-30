# 0007. Інфраструктура в Terraform

## Контекст
Auth (Cognito), щотижневий звіт і парсер агенди жили в трьох CloudFormation-шаблонах. Вони працювали, але були прив'язані до одного AWS-акаунта, а проєкт уже виходить за межі AWS (Google OAuth, GitHub) і йому потрібне друге середовище.

## Рішення
Auth, reports і ai описані в Terraform у `infra/`. Стан зберігається в HCP Terraform, workspace `meetings-dev`. HCP Terraform сам запускає plan і apply з короткоживучими AWS-ключами через OIDC. Ресурси не перестворювали: стеки видалили з DeletionPolicy: Retain, а ресурси імпортували через import-блоки. Стеки ecr, backend і frontend лишилися в CloudFormation.

## Альтернативи
- CloudFormation: простіше, бо AWS сам тримає state, але тільки AWS і слабша мова для кількох середовищ.
- CDK: під капотом той самий CloudFormation, тож обмеження одного акаунта лишається.
- OpenTofu: сумісний з Terraform, але інтеграція з HCP Terraform не така пряма, а відкрита ліцензія нам зараз не потрібна.

## Наслідки
- Хто змінює інфру: будь-хто через pull request. У чеку видно plan, після review і merge у main HCP Terraform робить apply сам. Apply з ноутбука не робимо, у Makefile його немає. AI-асистент може відкрити PR, але не apply.
- Секрети: `google_client_secret` і `db_password` лежать як sensitive-змінні в workspace, у Git їх немає. У state вони є у відкритому вигляді, тому доступ до workspace дорівнює доступу до секретів.
- Google-провайдер Cognito має ignore_changes на provider_details, тому зміна client secret у workspace не потрапляє в Cognito автоматично.
- Якщо HCP Terraform недоступний: уже розгорнуте працює далі, бо Terraform не в рантаймі, а застосунок деплоїться через GitHub Actions. Змінити інфру в цей час не можна. У крайньому разі правимо в консолі й одразу повторюємо ту саму зміну в коді.
- Мінус: state тепер наш, ми відповідаємо за доступи до workspace.
