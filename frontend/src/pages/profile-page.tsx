import { zodResolver } from '@hookform/resolvers/zod'
import { ArrowLeftIcon, LogOutIcon } from 'lucide-react'
import { useState, type ReactNode } from 'react'
import { Controller, useForm } from 'react-hook-form'
import { Link } from 'react-router'
import { toast } from 'sonner'
import { z } from 'zod'

import { PasswordInput } from '@/components/auth-layout'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import {
  useAuth,
  useChangeEmail,
  useChangePassword,
  useConfirmEmail,
  useResendEmailCode,
  useUpdateName,
  type User,
} from '@/lib/auth'

export function ProfilePage() {
  const { user, signOut } = useAuth()
  // RequireAuth renders this page only with a user.
  if (!user) return null

  return (
    <div className="flex min-h-svh flex-col">
      <header className="flex items-center gap-3 px-3 py-2.5 md:px-5">
        <Button variant="ghost" size="icon-sm" asChild>
          <Link to="/home" aria-label="Back to meetings" title="Back to meetings">
            <ArrowLeftIcon />
          </Link>
        </Button>
        <h1 className="text-3xl leading-none">Profile</h1>
      </header>
      <div className="hairline" />

      <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 py-6">
        <div className="flex items-center gap-4 px-2">
          <span className="flex size-14 shrink-0 items-center justify-center rounded-full bg-secondary text-2xl font-semibold text-secondary-foreground">
            {user.name.charAt(0).toUpperCase()}
          </span>
          <div className="min-w-0">
            <p className="truncate text-xl font-semibold">{user.name}</p>
            <p className="truncate text-muted-foreground">{user.email}</p>
          </div>
        </div>

        {user.provider === 'google' ? (
          <Alert>
            <AlertDescription>
              You sign in with Google, so your name, email and password are managed in your Google
              account. Changes there show up here the next time you sign in.
            </AlertDescription>
          </Alert>
        ) : (
          <>
            <NameSection user={user} />
            <EmailSection user={user} />
            <PasswordSection />
          </>
        )}

        <Button variant="outline" className="self-start" onClick={signOut}>
          <LogOutIcon />
          Sign out
        </Button>
      </main>
    </div>
  )
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-4 rounded-[28px] bg-card px-6 py-6 sm:px-8">
      <h2 className="text-2xl leading-none">{title}</h2>
      {children}
    </section>
  )
}

const nameSchema = z.object({ name: z.string().trim().min(1, 'Enter your name').max(100) })

function NameSection({ user }: { user: User }) {
  const updateName = useUpdateName()
  const form = useForm<z.infer<typeof nameSchema>>({
    resolver: zodResolver(nameSchema),
    values: { name: user.name },
  })

  const onSubmit = form.handleSubmit(({ name }) =>
    updateName.mutate(name.trim(), {
      onSuccess: () => toast.success('Name updated'),
      onError: (error) => form.setError('root', { message: error.message }),
    }),
  )

  return (
    <Section title="Name">
      <form onSubmit={onSubmit} noValidate>
        <FieldGroup className="gap-4">
          <Controller
            name="name"
            control={form.control}
            render={({ field, fieldState }) => (
              <Field data-invalid={fieldState.invalid}>
                <FieldLabel htmlFor="profile-name">Name</FieldLabel>
                <Input
                  id="profile-name"
                  autoComplete="name"
                  aria-invalid={fieldState.invalid}
                  {...field}
                />
                <FieldError errors={[fieldState.error]} />
              </Field>
            )}
          />
          {form.formState.errors.root && (
            <FieldError>{form.formState.errors.root.message}</FieldError>
          )}
          <Button
            type="submit"
            className="self-start"
            disabled={updateName.isPending || !form.formState.isDirty}
          >
            {updateName.isPending ? 'Saving...' : 'Save name'}
          </Button>
        </FieldGroup>
      </form>
    </Section>
  )
}

const emailSchema = z.object({ email: z.email('Enter a valid email') })
const codeSchema = z.object({ code: z.string().trim().min(1, 'Enter the code from the email') })

/** Two steps: the new address, then the code Cognito emails to it. */
function EmailSection({ user }: { user: User }) {
  const changeEmail = useChangeEmail()
  const confirmEmail = useConfirmEmail()
  const resendCode = useResendEmailCode()
  const [pendingEmail, setPendingEmail] = useState<string | null>(null)

  const emailForm = useForm<z.infer<typeof emailSchema>>({
    resolver: zodResolver(emailSchema),
    defaultValues: { email: '' },
  })
  const codeForm = useForm<z.infer<typeof codeSchema>>({
    resolver: zodResolver(codeSchema),
    defaultValues: { code: '' },
  })

  const onSubmitEmail = emailForm.handleSubmit(({ email }) => {
    if (email.toLowerCase() === user.email.toLowerCase()) {
      emailForm.setError('email', { message: 'This is already your email' })
      return
    }
    changeEmail.mutate(email, {
      onSuccess: ({ needsConfirmation }) => {
        if (needsConfirmation) {
          codeForm.reset()
          setPendingEmail(email)
        } else {
          emailForm.reset()
          toast.success('Email updated')
        }
      },
      onError: (error) => emailForm.setError('root', { message: error.message }),
    })
  })

  const onSubmitCode = codeForm.handleSubmit(({ code }) =>
    confirmEmail.mutate(code.trim(), {
      onSuccess: () => {
        setPendingEmail(null)
        emailForm.reset()
        toast.success('Email updated')
      },
      onError: (error) => codeForm.setError('root', { message: error.message }),
    }),
  )

  const resend = () =>
    resendCode.mutate(undefined, {
      onSuccess: () => toast.success(`New code sent to ${pendingEmail}`),
      onError: (error) => codeForm.setError('root', { message: error.message }),
    })

  if (pendingEmail) {
    return (
      <Section title="Email">
        <form onSubmit={onSubmitCode} noValidate>
          <FieldGroup className="gap-4">
            <Controller
              name="code"
              control={codeForm.control}
              render={({ field, fieldState }) => (
                <Field data-invalid={fieldState.invalid}>
                  <FieldLabel htmlFor="profile-email-code">Verification code</FieldLabel>
                  <Input
                    id="profile-email-code"
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    autoFocus
                    aria-invalid={fieldState.invalid}
                    {...field}
                  />
                  <FieldDescription>
                    We sent a code to <strong>{pendingEmail}</strong>. Your email changes once you
                    enter it.
                  </FieldDescription>
                  <FieldError errors={[fieldState.error]} />
                </Field>
              )}
            />
            {codeForm.formState.errors.root && (
              <FieldError>{codeForm.formState.errors.root.message}</FieldError>
            )}
            <div className="flex flex-wrap gap-2">
              <Button type="submit" disabled={confirmEmail.isPending}>
                {confirmEmail.isPending ? 'Verifying...' : 'Verify email'}
              </Button>
              <Button
                type="button"
                variant="outline"
                disabled={resendCode.isPending}
                onClick={resend}
              >
                Send a new code
              </Button>
              <Button type="button" variant="ghost" onClick={() => setPendingEmail(null)}>
                Cancel
              </Button>
            </div>
          </FieldGroup>
        </form>
      </Section>
    )
  }

  return (
    <Section title="Email">
      <form onSubmit={onSubmitEmail} noValidate>
        <FieldGroup className="gap-4">
          <Controller
            name="email"
            control={emailForm.control}
            render={({ field, fieldState }) => (
              <Field data-invalid={fieldState.invalid}>
                <FieldLabel htmlFor="profile-email">New email</FieldLabel>
                <Input
                  id="profile-email"
                  type="email"
                  autoComplete="email"
                  placeholder={user.email}
                  aria-invalid={fieldState.invalid}
                  {...field}
                />
                <FieldDescription>You will sign in with the new email.</FieldDescription>
                <FieldError errors={[fieldState.error]} />
              </Field>
            )}
          />
          {emailForm.formState.errors.root && (
            <FieldError>{emailForm.formState.errors.root.message}</FieldError>
          )}
          <Button type="submit" className="self-start" disabled={changeEmail.isPending}>
            {changeEmail.isPending ? 'Sending code...' : 'Change email'}
          </Button>
        </FieldGroup>
      </form>
    </Section>
  )
}

// Mirrors the Cognito password policy (infra/auth.yaml), like the signup form.
const passwordSchema = z
  .object({
    currentPassword: z.string().min(1, 'Enter your current password'),
    newPassword: z.string().min(8, 'Use at least 8 characters'),
    confirmPassword: z.string(),
  })
  .refine((v) => v.newPassword === v.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  })

type PasswordValues = z.infer<typeof passwordSchema>

const PASSWORD_FIELDS: {
  name: keyof PasswordValues
  label: string
  autoComplete: string
}[] = [
  { name: 'currentPassword', label: 'Current password', autoComplete: 'current-password' },
  { name: 'newPassword', label: 'New password', autoComplete: 'new-password' },
  { name: 'confirmPassword', label: 'Confirm new password', autoComplete: 'new-password' },
]

function PasswordSection() {
  const changePassword = useChangePassword()
  const form = useForm<PasswordValues>({
    resolver: zodResolver(passwordSchema),
    defaultValues: { currentPassword: '', newPassword: '', confirmPassword: '' },
  })

  const onSubmit = form.handleSubmit(({ currentPassword, newPassword }) =>
    changePassword.mutate(
      { currentPassword, newPassword },
      {
        onSuccess: () => {
          form.reset()
          toast.success('Password changed')
        },
        onError: (error) => form.setError('root', { message: error.message }),
      },
    ),
  )

  return (
    <Section title="Password">
      <form onSubmit={onSubmit} noValidate>
        <FieldGroup className="gap-4">
          {PASSWORD_FIELDS.map(({ name, label, autoComplete }) => (
            <Controller
              key={name}
              name={name}
              control={form.control}
              render={({ field, fieldState }) => (
                <Field data-invalid={fieldState.invalid}>
                  <FieldLabel htmlFor={`profile-${name}`}>{label}</FieldLabel>
                  <PasswordInput
                    id={`profile-${name}`}
                    autoComplete={autoComplete}
                    aria-invalid={fieldState.invalid}
                    {...field}
                  />
                  <FieldError errors={[fieldState.error]} />
                </Field>
              )}
            />
          ))}
          {form.formState.errors.root && (
            <FieldError>{form.formState.errors.root.message}</FieldError>
          )}
          <Button type="submit" className="self-start" disabled={changePassword.isPending}>
            {changePassword.isPending ? 'Changing...' : 'Change password'}
          </Button>
        </FieldGroup>
      </form>
    </Section>
  )
}
