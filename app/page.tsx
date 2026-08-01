import type { Metadata } from 'next'
import Image from 'next/image'
import Link from 'next/link'
import { ArrowRight, BarChart3, Check, Code2, LockKeyhole, Scale, TrendingUp } from 'lucide-react'
import coverImage from '../public/readme-cover-concept-b.png'

export const metadata: Metadata = {
  title: 'OpenSourcingOS — Procurement Savings, Tracked Properly',
  description: 'An open-source procurement value tracker for baselines, supplier offers, savings schedules, fiscal-year reporting, and realization.',
}

const features = [
  {
    title: 'Defensible savings',
    description: 'Keep opening proposals, spend baselines, and final offers connected so every reported figure has an audit trail.',
    icon: Scale,
  },
  {
    title: 'Fiscal-year clarity',
    description: 'Schedule savings by month, year, or one-time period without changing the underlying deal economics.',
    icon: BarChart3,
  },
  {
    title: 'Realization, not promises',
    description: 'Separate forecast, booked, and realized value so pipeline never quietly becomes reported savings.',
    icon: TrendingUp,
  },
]

export default function HomePage() {
  return (
    <main className="min-h-screen overflow-hidden bg-[#f8f8ff] text-[#11162f] dark:bg-[#090d1b] dark:text-white">
      <div className="pointer-events-none absolute inset-x-0 top-0 -z-0 h-[720px] bg-[radial-gradient(circle_at_78%_12%,rgba(79,70,229,0.18),transparent_42%)]" />

      <header className="relative z-10 mx-auto flex w-full max-w-7xl items-center justify-between px-5 py-5 sm:px-8 lg:px-10">
        <Link href="/" className="flex items-center gap-2" aria-label="OpenSourcingOS home">
          <span className="text-lg font-semibold tracking-tight sm:text-xl">OpenSourcing</span>
          <span className="grid h-8 w-8 place-items-center rounded-lg bg-[#4f46e5] text-sm font-bold text-white">OS</span>
        </Link>

        <nav className="flex items-center gap-2" aria-label="Public navigation">
          <a
            href="https://github.com/gruvyo/opensourcingos"
            className="hidden items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium text-slate-600 transition-colors hover:bg-white hover:text-slate-950 dark:text-slate-300 dark:hover:bg-white/10 dark:hover:text-white sm:inline-flex"
          >
            <Code2 className="h-4 w-4" aria-hidden="true" />
            GitHub
          </a>
          <Link
            href="/login"
            className="inline-flex items-center gap-2 rounded-lg bg-[#4f46e5] px-4 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-[#4338ca] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4f46e5] focus-visible:ring-offset-2"
          >
            Try the demo
            <ArrowRight className="h-4 w-4" aria-hidden="true" />
          </Link>
        </nav>
      </header>

      <section className="relative z-10 mx-auto w-full max-w-7xl px-5 pb-16 pt-14 text-center sm:px-8 sm:pt-20 lg:px-10 lg:pt-24">
        <div className="mx-auto inline-flex items-center gap-2 rounded-full border border-indigo-200 bg-white/80 px-3 py-1.5 text-xs font-semibold text-indigo-700 shadow-sm backdrop-blur dark:border-indigo-400/20 dark:bg-indigo-400/10 dark:text-indigo-200">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
          Open source · Public beta
        </div>
        <h1 className="mx-auto mt-6 max-w-4xl text-balance text-4xl font-bold tracking-[-0.04em] sm:text-6xl lg:text-7xl">
          Procurement savings,
          <span className="block text-[#4f46e5] dark:text-indigo-300">tracked properly.</span>
        </h1>
        <p className="mx-auto mt-6 max-w-2xl text-pretty text-base leading-7 text-slate-600 dark:text-slate-300 sm:text-lg">
          Connect sourcing projects, baselines, supplier offers, savings schedules, and realization in one transparent portfolio.
        </p>

        <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <Link
            href="/login"
            className="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-[#4f46e5] px-5 py-3 text-sm font-semibold text-white shadow-[0_14px_30px_-16px_rgba(79,70,229,0.75)] transition-all hover:-translate-y-0.5 hover:bg-[#4338ca] sm:w-auto"
          >
            Explore a private demo
            <ArrowRight className="h-4 w-4" aria-hidden="true" />
          </Link>
          <a
            href="https://github.com/gruvyo/opensourcingos"
            className="inline-flex w-full items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-5 py-3 text-sm font-semibold text-slate-800 shadow-sm transition-all hover:-translate-y-0.5 hover:border-indigo-200 dark:border-white/15 dark:bg-white/5 dark:text-white dark:hover:bg-white/10 sm:w-auto"
          >
            <Code2 className="h-4 w-4" aria-hidden="true" />
            View the source
          </a>
        </div>
        <p className="mt-4 inline-flex items-center gap-1.5 text-xs text-slate-500 dark:text-slate-400">
          <LockKeyhole className="h-3.5 w-3.5" aria-hidden="true" />
          Google sign-in creates an isolated sample workspace. Do not use confidential data during beta.
        </p>

        <div className="relative mx-auto mt-12 max-w-6xl sm:mt-16">
          <div className="absolute inset-x-[12%] bottom-[-8%] h-[36%] rounded-full bg-indigo-500/20 blur-3xl" />
          <div className="relative overflow-hidden rounded-2xl border border-indigo-100 bg-white p-1.5 shadow-[0_36px_90px_-34px_rgba(31,38,99,0.45)] dark:border-white/10 dark:bg-white/5 sm:rounded-3xl sm:p-2">
            <Image
              src={coverImage}
              alt="OpenSourcingOS product direction across desktop, tablet, and mobile"
              priority
              placeholder="blur"
              sizes="(max-width: 1280px) 94vw, 1152px"
              className="h-auto w-full rounded-xl sm:rounded-[1.15rem]"
            />
          </div>
          <p className="mt-3 text-xs text-slate-500 dark:text-slate-400">Product direction concept · live functionality is evolving toward this experience</p>
        </div>
      </section>

      <section className="relative border-y border-indigo-100 bg-white/80 dark:border-white/10 dark:bg-white/[0.03]">
        <div className="mx-auto grid w-full max-w-7xl grid-cols-1 gap-px px-5 py-5 sm:px-8 md:grid-cols-3 lg:px-10">
          <MethodStep label="Opening proposal" />
          <MethodStep label="Defensible baseline" />
          <MethodStep label="Final offer" />
        </div>
      </section>

      <section className="mx-auto w-full max-w-7xl px-5 py-20 sm:px-8 lg:px-10 lg:py-24">
        <div className="max-w-2xl">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#4f46e5] dark:text-indigo-300">Built for credibility</p>
          <h2 className="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">A savings number should survive the follow-up question.</h2>
          <p className="mt-4 leading-7 text-slate-600 dark:text-slate-300">
            OpenSourcingOS is designed around traceability: what changed, compared with which commercial anchor, over what period, and with what confidence.
          </p>
        </div>

        <div className="mt-10 grid grid-cols-1 gap-5 md:grid-cols-3">
          {features.map(feature => {
            const Icon = feature.icon
            return (
              <article key={feature.title} className="rounded-2xl border border-slate-200 bg-white p-6 shadow-[0_16px_40px_-32px_rgba(15,23,42,0.5)] dark:border-white/10 dark:bg-white/5">
                <div className="grid h-10 w-10 place-items-center rounded-xl bg-indigo-50 text-[#4f46e5] dark:bg-indigo-400/10 dark:text-indigo-300">
                  <Icon className="h-5 w-5" aria-hidden="true" />
                </div>
                <h3 className="mt-5 text-lg font-semibold">{feature.title}</h3>
                <p className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">{feature.description}</p>
              </article>
            )
          })}
        </div>
      </section>

      <section className="mx-auto w-full max-w-7xl px-5 pb-20 sm:px-8 lg:px-10 lg:pb-24">
        <div className="overflow-hidden rounded-3xl bg-[#11162f] px-6 py-10 text-white shadow-2xl sm:px-10 lg:flex lg:items-center lg:justify-between lg:px-12">
          <div className="max-w-2xl">
            <div className="flex items-center gap-2 text-sm font-medium text-indigo-200">
              <Check className="h-4 w-4" aria-hidden="true" />
              Apache 2.0 licensed
            </div>
            <h2 className="mt-3 text-3xl font-bold tracking-tight">Explore it, question it, help improve it.</h2>
            <p className="mt-3 text-sm leading-6 text-slate-300">The methodology is executable, the security model is documented, and contributions are welcome.</p>
          </div>
          <div className="mt-7 flex flex-col gap-3 sm:flex-row lg:mt-0">
            <a href="https://github.com/gruvyo/opensourcingos" className="inline-flex items-center justify-center gap-2 rounded-xl border border-white/20 px-5 py-3 text-sm font-semibold transition-colors hover:bg-white/10">
              <Code2 className="h-4 w-4" aria-hidden="true" />
              GitHub repository
            </a>
            <Link href="/login" className="inline-flex items-center justify-center gap-2 rounded-xl bg-white px-5 py-3 text-sm font-semibold text-[#11162f] transition-colors hover:bg-indigo-50">
              Try the demo
              <ArrowRight className="h-4 w-4" aria-hidden="true" />
            </Link>
          </div>
        </div>
      </section>

      <footer className="border-t border-slate-200 px-5 py-8 text-center text-xs text-slate-500 dark:border-white/10 dark:text-slate-400">
        OpenSourcingOS · Open-source procurement value tracking
      </footer>
    </main>
  )
}

function MethodStep({ label }: { label: string }) {
  return (
    <div className="flex items-center justify-center gap-3 px-4 py-3 text-sm font-medium text-slate-700 dark:text-slate-200">
      <span className="h-2.5 w-2.5 rounded-full bg-[#4f46e5] ring-4 ring-indigo-100 dark:ring-indigo-400/15" />
      {label}
    </div>
  )
}
