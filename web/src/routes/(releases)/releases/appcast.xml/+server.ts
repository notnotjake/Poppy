import { site } from '$lib/site-config'
import { listAppcastReleases } from '$lib/server/releases'

const appcastCacheControl = 'public, max-age=300, stale-while-revalidate=3600'

function absoluteUrl(path: string) {
	return new URL(path, site.url).toString()
}

function escapeXml(value: string | number) {
	return String(value)
		.replaceAll('&', '&amp;')
		.replaceAll('<', '&lt;')
		.replaceAll('>', '&gt;')
		.replaceAll('"', '&quot;')
		.replaceAll("'", '&apos;')
}

export async function GET() {
	const releases = await listAppcastReleases()
	const fullReleaseNotesUrl = absoluteUrl('/releases/changelog')
	const items = releases
		.map((release) => {
			const releaseNotesUrl = absoluteUrl(`/releases/${release.version}`)
			const downloadUrl = absoluteUrl(`/download/${release.version}/zip`)

			return `
		<item>
			<title>${escapeXml(release.title)}</title>
			<link>${escapeXml(releaseNotesUrl)}</link>
			<sparkle:version>${escapeXml(release.build)}</sparkle:version>
			<sparkle:shortVersionString>${escapeXml(release.version)}</sparkle:shortVersionString>
			<sparkle:releaseNotesLink>${escapeXml(releaseNotesUrl)}</sparkle:releaseNotesLink>
			<sparkle:fullReleaseNotesLink>${escapeXml(fullReleaseNotesUrl)}</sparkle:fullReleaseNotesLink>
			<pubDate>${escapeXml(release.publishedAt.toUTCString())}</pubDate>
			<enclosure
				url="${escapeXml(downloadUrl)}"
				length="${escapeXml(release.sparkleZipLength)}"
				type="application/octet-stream"
				sparkle:edSignature="${escapeXml(release.sparkleZipSignature)}" />
		</item>`
		})
		.join('')

	const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
	<channel>
		<title>${escapeXml(site.name)} Updates</title>
		<link>${escapeXml(site.url)}</link>
		<description>${escapeXml(`${site.name} release updates`)}</description>${items}
	</channel>
</rss>
`

	return new Response(xml, {
		headers: {
			'cache-control': appcastCacheControl,
			'content-type': 'application/rss+xml; charset=utf-8'
		}
	})
}
