<script lang="ts">
	import { resolve } from '$app/paths'

	import { IconArrowNarrowDown } from '@tabler/icons-svelte'
	import { Color } from '$ui/color'

	const PAGE_BACKGROUND = '#F7F7F7'
	const HERO_TOP_BACKGROUND = '#D4D4D4'
	const HERO_VIDEO_SRC = resolve('/field-video-slowmo-4x-60fps-h264.mp4')
	const DOWNLOAD_URL = resolve('/download')
</script>

<Color.HTMLBackground color={PAGE_BACKGROUND} />
<Color.BodyBackground color={PAGE_BACKGROUND} />

<div class="overscroll-top" style:background-color={HERO_TOP_BACKGROUND}></div>

<main
	class="relative isolate flex min-h-screen items-center justify-center overflow-hidden px-6"
	style:background={`linear-gradient(to bottom, ${PAGE_BACKGROUND}, ${HERO_TOP_BACKGROUND})`}
>
	<div class="hero-video-shell" aria-hidden="true">
		<video class="hero-video" src={HERO_VIDEO_SRC} autoplay muted playsinline preload="auto"
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

		<!-- Download Button -->
		<a
			class="bg-black/50 bg-blend-darken rounded-full pl-4 backdrop-blur-md px-6 py-3 flex items-center justify-center hover:bg-[#007AFF] transition-colors"
			href={DOWNLOAD_URL}
		>
			<IconArrowNarrowDown class="text-white" size={26} stroke={3} />
			<p class="text-white opacity-95 bg-blend-lighten text-lg font-semibold">Download</p>
		</a>
	</section>
</main>

<style>
	.hero-video-shell {
		position: absolute;
		inset: 48% auto auto 50%;
		z-index: 0;
		width: min(96vw, 96vh, 64rem);
		aspect-ratio: 1;
		translate: -50% -50%;
		pointer-events: none;
		overflow: visible;
		-webkit-mask-image: var(--hero-video-mask);
		mask-image: var(--hero-video-mask);
		-webkit-mask-mode: alpha;
		mask-mode: alpha;
		-webkit-mask-repeat: no-repeat;
		mask-repeat: no-repeat;
		-webkit-mask-size: 100% 100%;
		mask-size: 100% 100%;
		--hero-video-mask: radial-gradient(
			circle closest-side at center,
			black 0 58%,
			rgb(0 0 0 / 0.82) 68%,
			rgb(0 0 0 / 0.38) 82%,
			rgb(0 0 0 / 0.08) 94%,
			transparent 100%
		);
	}

	.hero-video {
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: center;
		scale: 1.22;
	}
</style>
