package com.amazon.kindle.kindlet;

public abstract class AbstractKindlet implements Kindlet {
    public void create(KindletContext context) { }
    public void start() { }
    public void stop() { }
    public void destroy() { }
}
