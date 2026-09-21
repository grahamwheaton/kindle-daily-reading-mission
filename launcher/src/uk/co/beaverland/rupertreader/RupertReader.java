package uk.co.beaverland.rupertreader;

import com.amazon.kindle.kindlet.AbstractKindlet;
import com.amazon.kindle.kindlet.KindletContext;
import java.awt.BorderLayout;
import java.awt.Container;
import java.awt.Font;
import java.awt.Label;

/** Minimal KDK 1.0 compatibility probe. */
public final class RupertReader extends AbstractKindlet {
    private KindletContext context;

    public void create(KindletContext value) {
        context = value;
        Container root = context.getRootContainer();
        root.removeAll();
        root.setLayout(new BorderLayout());
        Label title = new Label("RUPERT'S READER v10", Label.CENTER);
        title.setFont(new Font("SansSerif", Font.BOLD, 28));
        root.add(title, BorderLayout.CENTER);
        root.validate();
    }

    public void start() {
        try { context.setSubTitle("Compatibility test"); } catch (Throwable ignored) { }
    }

    public void stop() { }

    public void destroy() {
        context = null;
    }
}
