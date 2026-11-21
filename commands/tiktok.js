const axios = require('axios');

const TIKTOK_URL_RE = /https?:\/\/(?:www\.|vm\.|vt\.|m\.)?tiktok\.com\/[^\s]+/i;
const MAX_BYTES = 60 * 1024 * 1024; // stay safely under WhatsApp's media limit

const channelInfo = {
    contextInfo: {
        forwardingScore: 999,
        isForwarded: true,
        forwardedNewsletterMessageInfo: {
            newsletterJid: '120363161513685998@newsletter',
            newsletterName: 'KnightBot MD',
            serverMessageId: -1
        }
    }
};

// Resolve a TikTok link (short or full) to video/photo/audio info via tikwm.com
async function fetchTikTok(url) {
    const params = new URLSearchParams({ url, hd: '1' });
    const { data } = await axios.post('https://www.tikwm.com/api/', params.toString(), {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: 30000
    });
    if (!data || data.code !== 0 || !data.data) {
        throw new Error(data?.msg || 'Could not resolve TikTok link');
    }
    return data.data;
}

async function downloadBuffer(url) {
    const res = await axios.get(url, {
        responseType: 'arraybuffer',
        timeout: 120000,
        maxContentLength: MAX_BYTES,
        headers: { 'User-Agent': 'Mozilla/5.0' }
    });
    return Buffer.from(res.data);
}

function formatCount(n) {
    if (typeof n !== 'number') return '0';
    if (n >= 1e6) return (n / 1e6).toFixed(1).replace(/\.0$/, '') + 'M';
    if (n >= 1e3) return (n / 1e3).toFixed(1).replace(/\.0$/, '') + 'K';
    return String(n);
}

/**
 * .tiktok <url>     -> video without watermark (or photos for slideshow posts)
 * .tiktokmp3 <url>  -> audio only
 * `rawText` must be the original (non-lowercased) message, because TikTok links are case-sensitive.
 */
async function tiktokCommand(sock, chatId, message, rawText, audioOnly = false) {
    const match = rawText.match(TIKTOK_URL_RE);
    if (!match) {
        await sock.sendMessage(chatId, {
            text: `❌ Please provide a TikTok link!\n\nExample: .tiktok https://www.tiktok.com/t/ZPN2RRRCT/`,
            ...channelInfo
        }, { quoted: message });
        return;
    }

    try {
        await sock.sendMessage(chatId, { text: '⏳ Downloading from TikTok, please wait...', ...channelInfo }, { quoted: message });

        const info = await fetchTikTok(match[0]);
        const author = info.author?.unique_id ? `@${info.author.unique_id}` : 'unknown';
        const caption = `🎬 *TikTok Downloader*\n\n` +
            `👤 *Author:* ${author}\n` +
            (info.title ? `📝 *Caption:* ${info.title.slice(0, 300)}\n` : '') +
            `❤️ ${formatCount(info.digg_count)}  💬 ${formatCount(info.comment_count)}  ▶️ ${formatCount(info.play_count)}\n\n` +
            `_Powered by ${global.botname || 'KnightBot MD'}_`;

        if (audioOnly) {
            const audioUrl = info.music_info?.play || info.music;
            if (!audioUrl) throw new Error('No audio found for this post');
            const audio = await downloadBuffer(audioUrl);
            await sock.sendMessage(chatId, {
                audio,
                mimetype: 'audio/mpeg',
                fileName: `${info.music_info?.title || 'tiktok'}.mp3`
            }, { quoted: message });
            return;
        }

        // Photo slideshow posts
        if (Array.isArray(info.images) && info.images.length) {
            const images = info.images.slice(0, 20);
            for (let i = 0; i < images.length; i++) {
                const img = await downloadBuffer(images[i]);
                await sock.sendMessage(chatId, {
                    image: img,
                    caption: i === 0 ? caption : undefined
                }, { quoted: i === 0 ? message : undefined });
            }
            return;
        }

        // Video: prefer HD if within the size limit, otherwise standard quality
        const candidates = [];
        if (info.hdplay && (!info.hd_size || info.hd_size <= MAX_BYTES)) candidates.push(info.hdplay);
        if (info.play) candidates.push(info.play);
        if (!candidates.length) throw new Error('No downloadable video found');

        let video;
        let lastErr;
        for (const url of candidates) {
            try {
                video = await downloadBuffer(url);
                break;
            } catch (err) {
                lastErr = err;
            }
        }
        if (!video) throw lastErr || new Error('Video download failed');

        await sock.sendMessage(chatId, {
            video,
            mimetype: 'video/mp4',
            caption
        }, { quoted: message });
    } catch (error) {
        console.error('Error in tiktok command:', error.message);
        await sock.sendMessage(chatId, {
            text: '❌ Failed to download the TikTok. Make sure the link is valid and the post is public, then try again.',
            ...channelInfo
        }, { quoted: message });
    }
}

module.exports = tiktokCommand;
