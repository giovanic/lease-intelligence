import type { ReactNode } from 'react'
import { translateError } from './validationMessages'

interface FormFieldProps {
  label: string
  /** The API's 422 messages for this field. */
  errors?: string[]
  hint?: string
  required?: boolean
  children: ReactNode
}

/** Label + control + hint/errors. The control itself is the child. */
export function FormField({ label, errors, hint, required, children }: FormFieldProps) {
  const invalid = errors !== undefined && errors.length > 0

  return (
    <label className={invalid ? 'field field--invalid' : 'field'}>
      <span className="field__label">
        {label}
        {required && <span aria-hidden="true"> *</span>}
      </span>
      {children}
      {hint && !invalid && <span className="field__hint">{hint}</span>}
      {invalid && <span className="field__error">{errors.map(translateError).join('; ')}</span>}
    </label>
  )
}
