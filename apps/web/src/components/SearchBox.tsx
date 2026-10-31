import { useState, type FormEvent } from 'react'

interface SearchBoxProps {
  /** The value currently applied (from the URL). */
  value: string
  placeholder: string
  onSearch: (value: string) => void
}

/** Free-text filter applied on submit (Enter or the button), not per keystroke. */
export function SearchBox({ value, placeholder, onSearch }: SearchBoxProps) {
  const [draft, setDraft] = useState(value)
  const [applied, setApplied] = useState(value)

  // Follow the URL when it changes elsewhere (back/forward, a cleared filter).
  if (value !== applied) {
    setApplied(value)
    setDraft(value)
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    onSearch(draft.trim())
  }

  return (
    <form className="search-box" role="search" onSubmit={handleSubmit}>
      <input
        type="search"
        aria-label={placeholder}
        placeholder={placeholder}
        value={draft}
        onChange={(event) => setDraft(event.target.value)}
      />
      <button type="submit" className="button button--secondary">
        Buscar
      </button>
    </form>
  )
}
