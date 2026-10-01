import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: 'Privacy notice | OpenSourcingOS',
  description: 'How the OpenSourcingOS hosted demo uses sign-in, workspace, and site-usage information.',
}

export default function PrivacyPage() {
  return (
    <main id="main-content" tabIndex={-1} className="min-h-screen bg-[#f8f8ff] px-5 py-10 text-[#11162f] dark:bg-[#090d1b] dark:text-white sm:py-16">
      <article className="mx-auto max-w-3xl">
        <Link href="/" className="text-sm font-semibold text-indigo-700 underline underline-offset-2 dark:text-indigo-300">
          OpenSourcingOS home
        </Link>
        <header className="mt-8 border-b border-slate-200 pb-8 dark:border-white/15">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-indigo-700 dark:text-indigo-300">Public beta</p>
          <h1 className="mt-3 text-4xl font-bold tracking-tight sm:text-5xl">Privacy notice</h1>
          <p className="mt-3 text-sm text-slate-500 dark:text-slate-400">Last updated October 1, 2026</p>
          <p className="mt-5 leading-7 text-slate-700 dark:text-slate-300">
            This notice describes the hosted OpenSourcingOS demo at opensourcingos.com. Independent deployments of the open-source code are operated by their own hosts.
          </p>
        </header>

        <div className="space-y-9 py-9 text-sm leading-7 text-slate-700 dark:text-slate-300 sm:text-base">
          <section aria-labelledby="information">
            <h2 id="information" className="text-xl font-semibold text-[#11162f] dark:text-white">Information used by the demo</h2>
            <ul className="mt-3 list-disc space-y-2 pl-5">
              <li><strong>Sign-in information.</strong> Google sign-in passes account information to Supabase Auth. The app stores your email address and display name in a workspace profile.</li>
              <li><strong>Workspace information.</strong> Your first sign-in creates a private workspace with example projects. Information you add or change, including project figures, supplier details, notes, and contact details, is stored in the demo database. Changes to some records are also recorded in workspace audit history.</li>
              <li><strong>Site usage.</strong> Vercel Web Analytics records aggregate page views and related details such as the page, referrer, approximate location, browser, and device. Its analytics are designed to avoid identifying individual visitors and do not use third-party analytics cookies. Hosting and authentication providers also process technical data needed to deliver and protect the service.</li>
            </ul>
          </section>

          <section aria-labelledby="purpose">
            <h2 id="purpose" className="text-xl font-semibold text-[#11162f] dark:text-white">How the information is used</h2>
            <p className="mt-3">We use it to sign you in, create and operate your isolated demo workspace, show your changes, troubleshoot problems, respond to requests, protect the service, and understand overall site usage.</p>
          </section>

          <section aria-labelledby="providers">
            <h2 id="providers" className="text-xl font-semibold text-[#11162f] dark:text-white">Services involved</h2>
            <p className="mt-3">Google provides sign-in, Supabase provides authentication and database hosting, and Vercel hosts the site and provides Web Analytics. Workspace records are not published in the public GitHub source repository.</p>
          </section>

          <section aria-labelledby="retention">
            <h2 id="retention" className="text-xl font-semibold text-[#11162f] dark:text-white">Retention and your choices</h2>
            <p className="mt-3">The demo does not automatically expire your account or workspace data. You can browse the public site without signing in. To ask about your data or request account and workspace deletion, email <a href="mailto:hello@opensourcingos.com" className="font-medium text-indigo-700 underline underline-offset-2 dark:text-indigo-300">hello@opensourcingos.com</a>. We will verify the request and explain any data that must be retained. Provider logs and aggregate analytics follow the providers&apos; retention practices.</p>
            <p className="mt-3">This is a public beta for exploration. Do not enter confidential procurement or personal information.</p>
          </section>

          <section aria-labelledby="contact">
            <h2 id="contact" className="text-xl font-semibold text-[#11162f] dark:text-white">Contact and changes</h2>
            <p className="mt-3">OpenSourcingOS can be contacted at <a href="mailto:hello@opensourcingos.com" className="font-medium text-indigo-700 underline underline-offset-2 dark:text-indigo-300">hello@opensourcingos.com</a>. We will update this page when the hosted demo&apos;s data practices change.</p>
          </section>
        </div>

        <footer className="border-t border-slate-200 pt-6 text-sm dark:border-white/15">
          <Link href="/login" className="font-medium text-indigo-700 underline underline-offset-2 dark:text-indigo-300">Return to sign-in</Link>
        </footer>
      </article>
    </main>
  )
}
