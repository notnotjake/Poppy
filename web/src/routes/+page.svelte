<script lang="ts">
	import { resolve } from '$app/paths'

	import { Color } from '$ui/color'

	const PAGE_BACKGROUND = '#F7F7F7'
	const HERO_TOP_BACKGROUND = '#D4D4D4'
	const HERO_VIDEO_SRC = resolve('/field-video.mp4')

	function slowVideo(event: Event) {
		if (event.currentTarget instanceof HTMLVideoElement) {
			event.currentTarget.playbackRate = 0.5
		}
	}
</script>

<Color.HTMLBackground color={PAGE_BACKGROUND} />
<Color.BodyBackground color={PAGE_BACKGROUND} />

<div class="overscroll-top" style:background-color={HERO_TOP_BACKGROUND}></div>

<main
	class="relative isolate flex min-h-screen items-center justify-center overflow-hidden px-6"
	style:background={`linear-gradient(to bottom, ${HERO_TOP_BACKGROUND}, ${PAGE_BACKGROUND} 50%, ${PAGE_BACKGROUND})`}
>
	<div class="hero-video-shell" aria-hidden="true">
		<video
			class="hero-video hero-video-glow"
			src={HERO_VIDEO_SRC}
			autoplay
			muted
			playsinline
			preload="auto"
			onloadedmetadata={slowVideo}
			oncanplay={slowVideo}
		></video>

		<video
			class="hero-video hero-video-main"
			src={HERO_VIDEO_SRC}
			autoplay
			muted
			playsinline
			preload="auto"
			onloadedmetadata={slowVideo}
			oncanplay={slowVideo}
		></video>
	</div>

	<section class="relative z-10 mx-auto flex max-w-7xl flex-col items-center gap-4 text-center">
		<h1 class="text-[clamp(3rem,10vw,7rem)] font-bold tracking-tight-md text-neutral-950">
			Poppy for Mac
		</h1>

		<p
			class="text-[clamp(1.8rem,3.3vw,4rem)] leading-[0.92] font-bold tracking-tight-md text-neutral-700"
		>
			Installing apps on Mac can be a breeze!
		</p>
	</section>
</main>

<style>
	.hero-video-shell {
		position: absolute;
		inset: 50% auto auto 50%;
		z-index: 0;
		width: min(88vw, 72rem);
		aspect-ratio: 1.85;
		translate: -50% -52%;
		border-radius: 9999px;
		opacity: 0.78;
		pointer-events: none;
		filter: drop-shadow(0 2rem 5rem color-mix(in srgb, var(--color-neutral-900) 14%, transparent));
		-webkit-mask-image: var(--hero-video-mask);
		mask-image: var(--hero-video-mask);
		-webkit-mask-mode: alpha;
		mask-mode: alpha;
		--hero-video-mask: radial-gradient(
			ellipse at center,
			black 0 42%,
			rgb(0 0 0 / 0.88) 54%,
			rgb(0 0 0 / 0.34) 68%,
			transparent 84%
		);
	}

	.hero-video-shell::after {
		content: '';
		position: absolute;
		inset: -3rem;
		border-radius: inherit;
		pointer-events: none;
		box-shadow: inset 0 0 7rem 4rem rgb(247 247 247 / 0.92);
	}

	.hero-video {
		position: absolute;
		inset: 50% auto auto 50%;
		width: 100%;
		height: 100%;
		translate: -50% -50%;
		object-fit: cover;
		object-position: center;
		scale: 1.28;
	}

	.hero-video-main {
		filter: saturate(1.06);
	}

	.hero-video-glow {
		scale: 1.36;
		filter: blur(1.25rem) saturate(1.08);
		opacity: 0.64;
	}
</style>
