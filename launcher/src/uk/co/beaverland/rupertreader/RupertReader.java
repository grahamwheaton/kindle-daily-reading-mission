package uk.co.beaverland.rupertreader;

import com.amazon.kindle.kindlet.AbstractKindlet;
import com.amazon.kindle.kindlet.KindletContext;
import java.awt.Canvas;
import java.awt.Color;
import java.awt.Container;
import java.awt.Font;
import java.awt.FontMetrics;
import java.awt.Graphics;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.io.BufferedReader;
import java.io.FileReader;

/** First safe K4 prototype: full-screen UI, D-pad focus and Home escape. */
public final class RupertReader extends AbstractKindlet {
    private KindletContext context;
    private ReaderCanvas canvas;

    public void create(KindletContext value) {
        context = value;
        Container root = context.getRootContainer();
        root.removeAll();
        canvas = new ReaderCanvas(context);
        root.add(canvas);
        root.validate();
    }

    public void start() {
        if (canvas != null) {
            canvas.reload();
            canvas.requestFocus();
            canvas.repaint();
        }
    }

    public void stop() { }
    public void destroy() { canvas = null; context = null; }

    private static final class ReaderCanvas extends Canvas implements KeyListener {
        private final KindletContext context;
        private String title = "THE MUDDY MOUNTAIN RESCUE";
        private String streak = "1 day streak";
        private int selected = 0;

        ReaderCanvas(KindletContext value) {
            context = value;
            setBackground(Color.white);
            setForeground(Color.black);
            setFocusable(true);
            setFocusTraversalKeysEnabled(false);
            addKeyListener(this);
        }

        void reload() {
            BufferedReader reader = null;
            try {
                reader = new BufferedReader(new FileReader("/mnt/us/rupert-mission/launcher.properties"));
                String line;
                while ((line = reader.readLine()) != null) {
                    int split = line.indexOf('=');
                    if (split < 1) continue;
                    String key = line.substring(0, split);
                    String value = line.substring(split + 1);
                    if ("title".equals(key) && value.length() > 0) title = value.toUpperCase();
                    if ("streak".equals(key) && value.length() > 0) streak = value + " day streak";
                }
            } catch (Throwable ignored) {
                // The first visual prototype has safe built-in fallback content.
            } finally {
                try { if (reader != null) reader.close(); } catch (Throwable ignored) { }
            }
        }

        public void paint(Graphics g) {
            int w = getWidth();
            g.setColor(Color.white);
            g.fillRect(0, 0, w, getHeight());
            g.setColor(Color.black);

            centered(g, "RUPERT'S READER", new Font("SansSerif", Font.BOLD, 28), 48);
            g.drawLine(55, 66, w - 55, 66);
            centered(g, "TODAY'S MISSION", new Font("SansSerif", Font.PLAIN, 18), 112);
            drawWrappedTitle(g, title, 155, w - 80);

            // High-contrast placeholder landscape: mountain, track and rescue truck.
            int cy = 330;
            int[] mx = {70, 190, 270, 360, 515};
            int[] my = {cy + 70, cy - 35, cy + 30, cy - 55, cy + 70};
            g.fillPolygon(mx, my, mx.length);
            g.setColor(Color.white);
            g.fillRect(235, cy + 34, 95, 35);
            g.fillRect(305, cy + 20, 45, 49);
            g.setColor(Color.black);
            g.fillOval(245, cy + 55, 28, 28);
            g.fillOval(315, cy + 55, 28, 28);

            drawChoice(g, "START READING", 485, selected == 0);
            drawFlame(g, w / 2 - 95, 545);
            centered(g, streak, new Font("SansSerif", Font.BOLD, 17), 573);
            drawChoice(g, "PREVIOUS MISSIONS  >", 650, selected == 1);
            centered(g, "Use the arrows and centre button", new Font("SansSerif", Font.PLAIN, 13), 704);
        }

        private void drawChoice(Graphics g, String text, int y, boolean active) {
            Font font = new Font("SansSerif", Font.BOLD, 22);
            FontMetrics fm = g.getFontMetrics(font);
            int width = fm.stringWidth(text) + 46;
            int x = (getWidth() - width) / 2;
            if (active) {
                g.setColor(Color.black);
                g.fillRoundRect(x, y - 29, width, 42, 10, 10);
                g.setColor(Color.white);
            } else {
                g.setColor(Color.black);
                g.drawRoundRect(x, y - 29, width, 42, 10, 10);
            }
            g.setFont(font);
            g.drawString(text, x + 23, y);
            g.setColor(Color.black);
        }

        private void drawWrappedTitle(Graphics g, String value, int y, int maxWidth) {
            Font font = new Font("Serif", Font.BOLD, 28);
            FontMetrics fm = g.getFontMetrics(font);
            if (fm.stringWidth(value) <= maxWidth) {
                centered(g, value, font, y + 30);
                return;
            }
            int split = value.lastIndexOf(' ', value.length() / 2);
            if (split < 1) split = value.indexOf(' ', value.length() / 2);
            if (split < 1) {
                centered(g, value, font, y + 30);
            } else {
                centered(g, value.substring(0, split), font, y + 16);
                centered(g, value.substring(split + 1), font, y + 52);
            }
        }

        private void drawFlame(Graphics g, int x, int y) {
            int[] fx = {x, x + 13, x + 19, x + 29, x + 39, x + 35, x + 20, x + 5};
            int[] fy = {y + 25, y + 8, y + 18, y, y + 24, y + 39, y + 45, y + 38};
            g.fillPolygon(fx, fy, fx.length);
        }

        private void centered(Graphics g, String text, Font font, int baseline) {
            g.setFont(font);
            FontMetrics fm = g.getFontMetrics(font);
            g.drawString(text, (getWidth() - fm.stringWidth(text)) / 2, baseline);
        }

        public void keyPressed(KeyEvent event) {
            int code = event.getKeyCode();
            if (code == KeyEvent.VK_UP || code == KeyEvent.VK_LEFT) selected = 0;
            if (code == KeyEvent.VK_DOWN || code == KeyEvent.VK_RIGHT) selected = 1;
            if (code == KeyEvent.VK_ENTER) activate();
            repaint();
            event.consume();
        }

        private void activate() {
            if (selected == 0) {
                try {
                    Runtime.getRuntime().exec(new String[] {"/bin/sh", "/mnt/us/rupert-mission/open-current.sh"});
                    context.setSubTitle("Opening today's mission...");
                } catch (Throwable failure) {
                    context.setSubTitle("Launcher permission setup required");
                }
            } else {
                context.setSubTitle("Previous missions coming next");
            }
        }

        public void keyReleased(KeyEvent event) { event.consume(); }
        public void keyTyped(KeyEvent event) { event.consume(); }
    }
}
