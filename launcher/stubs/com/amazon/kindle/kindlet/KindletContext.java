package com.amazon.kindle.kindlet;

import java.awt.Container;
import java.io.File;

public interface KindletContext {
    Container getRootContainer();
    File getHomeDirectory();
    void setSubTitle(String subtitle);
}
