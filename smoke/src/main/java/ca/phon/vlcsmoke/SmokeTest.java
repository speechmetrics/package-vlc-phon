package ca.phon.vlcsmoke;

import com.sun.jna.NativeLibrary;
import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Pattern;
import uk.co.caprica.vlcj.binding.support.runtime.RuntimeUtil;
import uk.co.caprica.vlcj.factory.MediaPlayerFactory;
import uk.co.caprica.vlcj.factory.discovery.NativeDiscovery;
import uk.co.caprica.vlcj.log.LogLevel;
import uk.co.caprica.vlcj.log.NativeLog;
import uk.co.caprica.vlcj.player.base.MediaPlayer;
import uk.co.caprica.vlcj.player.base.MediaPlayerEventAdapter;
import uk.co.caprica.vlcj.player.embedded.EmbeddedMediaPlayer;
import uk.co.caprica.vlcj.player.embedded.videosurface.callback.BufferFormat;
import uk.co.caprica.vlcj.player.embedded.videosurface.callback.BufferFormatCallbackAdapter;
import uk.co.caprica.vlcj.player.embedded.videosurface.callback.RenderCallback;
import uk.co.caprica.vlcj.player.embedded.videosurface.callback.format.RV32BufferFormat;
import uk.co.caprica.vlcj.support.Info;

/**
 * Plays each test clip through a VLC package the way Phon does and checks that
 * it decodes.
 *
 * <p>Usage: {@code java -jar vlc-smoke.jar <vlc-lib-dir> <clips-dir> [allowed-errors-file]}
 * with {@code VLC_PLUGIN_PATH} set to the package's plug-in folder.
 */
public final class SmokeTest {

    private static final long TIMEOUT_MARGIN_MS = 20_000;

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: SmokeTest <vlc-lib-dir> <clips-dir> [allowed-errors-file]");
            System.exit(2);
        }
        File libDir = new File(args[0]).getAbsoluteFile();
        File clipsDir = new File(args[1]).getAbsoluteFile();
        List<Pattern> allowed = args.length > 2 ? readAllowed(new File(args[2])) : List.of();

        NativeLibrary.addSearchPath(RuntimeUtil.getLibVlcLibraryName(), libDir.getPath());

        // No native discovery: it would fall back to an installed VLC, and the
        // package must load on its own.
        MediaPlayerFactory factory = new MediaPlayerFactory(
                (NativeDiscovery) null, "--no-metadata-network-access", "--no-plugins-cache", "--aout=adummy");
        System.out.println("vlcj   " + Info.getInstance().vlcjVersion());
        System.out.println("libvlc " + factory.application().version());

        // JNA falls back to other search paths; make sure the package's own
        // libvlc is the one under test.
        File loaded = NativeLibrary.getInstance(RuntimeUtil.getLibVlcLibraryName())
                .getFile()
                .getCanonicalFile();
        System.out.println("loaded " + loaded);
        if (!loaded.toPath().startsWith(libDir.getCanonicalFile().toPath())) {
            System.err.println("libvlc was loaded from outside " + libDir);
            System.exit(1);
        }

        List<String> errors = Collections.synchronizedList(new ArrayList<>());
        NativeLog log = factory.application().newLog();
        log.setLevel(LogLevel.ERROR);
        log.addLogListener((level, module, file, line, name, header, id, message) -> {
            String entry = module + ": " + message;
            if (allowed.stream().noneMatch(p -> p.matcher(entry).find())) {
                errors.add(entry);
            }
        });

        File[] clips = clipsDir.listFiles(File::isFile);
        if (clips == null || clips.length == 0) {
            System.err.println("no clips in " + clipsDir);
            System.exit(2);
        }
        java.util.Arrays.sort(clips);

        int failed = 0;
        for (File clip : clips) {
            errors.clear();
            String failure = play(factory, clip, errors);
            if (failure == null) {
                System.out.println("PASS " + clip.getName());
            } else {
                System.out.println("FAIL " + clip.getName() + ": " + failure);
                failed++;
            }
        }

        log.release();
        factory.release();
        System.exit(failed == 0 ? 0 : 1);
    }

    /** Plays one clip; returns null on success or the reason it failed. */
    private static String play(MediaPlayerFactory factory, File clip, List<String> errors)
            throws InterruptedException, IOException {
        boolean video = clip.getName().startsWith("video");
        AtomicInteger frames = new AtomicInteger();
        CountDownLatch finished = new CountDownLatch(1);
        CountDownLatch firstFrame = new CountDownLatch(1);
        AtomicInteger encounteredError = new AtomicInteger();

        EmbeddedMediaPlayer player = factory.mediaPlayers().newEmbeddedMediaPlayer();
        try {
            player.videoSurface()
                    .set(factory.videoSurfaces()
                            .newVideoSurface(
                                    new BufferFormatCallbackAdapter() {
                                        @Override
                                        public BufferFormat getBufferFormat(int sourceWidth, int sourceHeight) {
                                            return new RV32BufferFormat(sourceWidth, sourceHeight);
                                        }
                                    },
                                    new RenderCallback() {
                                        @Override
                                        public void lock(MediaPlayer mediaPlayer) {}

                                        @Override
                                        public void unlock(MediaPlayer mediaPlayer) {}

                                        @Override
                                        public void display(
                                                MediaPlayer mediaPlayer,
                                                ByteBuffer[] nativeBuffers,
                                                BufferFormat bufferFormat,
                                                int width,
                                                int height) {
                                            frames.incrementAndGet();
                                            firstFrame.countDown();
                                        }
                                    },
                                    true));
            player.events().addMediaPlayerEventListener(new MediaPlayerEventAdapter() {
                @Override
                public void finished(MediaPlayer mediaPlayer) {
                    finished.countDown();
                }

                @Override
                public void error(MediaPlayer mediaPlayer) {
                    encounteredError.incrementAndGet();
                    finished.countDown();
                }
            });

            // Phon opens media with these options (PhonMediaPlayer.loadMedia).
            if (!player.media().play(clip.getPath(), ":no-video-title-show")) {
                return "media could not be opened";
            }

            File snapshot = null;
            if (video) {
                if (!firstFrame.await(TIMEOUT_MARGIN_MS, TimeUnit.MILLISECONDS)) {
                    return "no video frames";
                }
                snapshot = File.createTempFile("vlc-smoke", ".png");
                snapshot.delete();
                // The snapshot is written asynchronously after save() returns.
                if (!player.snapshots().save(snapshot)) {
                    return "snapshot failed";
                }
            }

            long length = Math.max(player.status().length(), 3_000);
            if (!finished.await(length + TIMEOUT_MARGIN_MS, TimeUnit.MILLISECONDS)) {
                return "did not finish playing";
            }
            if (encounteredError.get() > 0) {
                return "player reported an error";
            }
            if (video) {
                if (frames.get() == 0) {
                    return "no video frames";
                }
                if (!snapshot.isFile() || Files.size(snapshot.toPath()) == 0) {
                    return "snapshot file is empty";
                }
                snapshot.delete();
            }
            synchronized (errors) {
                if (!errors.isEmpty()) {
                    return "VLC errors: " + String.join(" | ", errors);
                }
            }
            return null;
        } finally {
            player.release();
        }
    }

    private static List<Pattern> readAllowed(File file) throws IOException {
        List<Pattern> patterns = new ArrayList<>();
        for (String line : Files.readAllLines(file.toPath())) {
            String trimmed = line.strip();
            if (!trimmed.isEmpty() && !trimmed.startsWith("#")) {
                patterns.add(Pattern.compile(trimmed));
            }
        }
        return patterns;
    }
}
