import { Link } from 'react-router'

import { useAuth } from '@/lib/auth'

export function ProfilePage() {
  const { user } = useAuth()
  return (
    <main style={{ padding: 24 }}>
      <h1>Profile</h1>
      <p>{user?.email}</p>
      <Link to="/home">Back</Link>
    </main>
  )
}
