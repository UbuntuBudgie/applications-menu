/*
 * Copyright 2019 elementary, Inc. (https://elementary.io)
 *           2011-2012 Giulio Collura
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

public class Slingshot.Widgets.Grid : Gtk.Grid {
    public signal void app_launched ();

    private struct Page {
        public uint rows;
        public uint columns;
    }

    private Gtk.Widget? focused_widget;
    private Gee.HashMap<int, Gtk.Grid> grids;
    private Gee.HashSet<int> filled_pages;
    private Gee.ArrayList<Backend.App> filtered_apps;
#if HANDY1
    private Hdy.Carousel paginator;
#else
    private Hdy.Paginator paginator;
#endif
    private Page page;
    private int apps_per_page = 1;
    private int total_page_count = 1;
    private uint background_fill_source = 0;

    private int focused_column;
    private int focused_row;

    private static GLib.Settings settings { get; private set; default = null; }
    static construct {
        settings = new GLib.Settings ("org.ubuntubudgie.plugins.budgie-appmenu");
    }

    construct {
        page.rows = 3;
        page.columns = 5;

#if HANDY1
        paginator = new Hdy.Carousel ();
#else
        paginator = new Hdy.Paginator ();
#endif
        paginator.expand = true;

        var page_switcher = new Widgets.Switcher ();
        page_switcher.set_paginator (paginator, this);

        orientation = Gtk.Orientation.VERTICAL;
        row_spacing = 24;
        margin_bottom = 12;
        add (paginator);
        add (page_switcher);

        grids = new Gee.HashMap<int, Gtk.Grid> (null, null);
        filled_pages = new Gee.HashSet<int> ();
        filtered_apps = new Gee.ArrayList<Backend.App> ();

        // Check when switching to specific pages rather then doing
        // things at a page at a time
        paginator.notify["position"].connect (() => {
            ensure_page_filled ((int) Math.round (paginator.position) + 1);
        });
    }

    public void populate (Backend.AppSystem app_system) {
        int app_count = 0;
        foreach (Gtk.Grid grid in grids.values) {
            grid.destroy ();
        }

        grids.clear ();
        filled_pages = new Gee.HashSet<int> ();
        filtered_apps = new Gee.ArrayList<Backend.App> ();

        page.rows = settings.get_int("rows");
        page.columns = settings.get_int("columns");
        apps_per_page = int.max (1, (int) (page.rows * page.columns));

        foreach (Backend.App app in app_system.get_apps_by_name ()) {
            if (!settings.get_boolean("show-terminal-apps") && app.terminal ) {
                continue;
            }
            filtered_apps.add (app);
        }

        total_page_count = int.max (1,
            (int) Math.ceil ((double) filtered_apps.size / (double) apps_per_page));

        // Build every page's empty container up front so the page switcher / dot count is accurate
        // right away. Only the currently-visible page gets its real
        // AppButtons attached now; the rest are filled lazily in
        // ensure_page_filled () the first time the user navigates there.
        // Building every page's AppButtons immediately is
        // causing big delays from recent changes in 26.10 - monitor this
        // in later versions to see if we can revert this
        for (int number = 1; number <= total_page_count; number++) {
            create_new_grid (number);
        }

        ensure_page_filled (1);
        paginator.scroll_to (grids.get (1));
        show_all ();
        //schedule_background_fill ();
    }

    private void create_new_grid (int number) {
        // Grid properties
        var grid = new Gtk.Grid ();
        grid.expand = true;
        grid.row_homogeneous = true;
        grid.column_homogeneous = true;
        grid.margin_start = 12;
        grid.margin_end = 12;

        grid.row_spacing = 24;
        grid.column_spacing = 0;
        grids.set (number, grid);
        paginator.add (grid);
        // Fake grids in case there are not enough apps to fill the grid
        for (var row = 0; row < page.rows; row++)
            for (var column = 0; column < page.columns; column++)
                grid.attach (new Gtk.Grid (), column, row, 1, 1);
    }

    // Attaches real AppButtons to an already-built (placeholder) page,
    // the first time that page is actually navigated to. No-op if the
    // page has already been filled.
    private void ensure_page_filled (int number) {
        if (number < 1 || number > total_page_count || filled_pages.contains (number)) {
            return;
        }

        Gtk.Grid? grid = grids.get (number);
        if (grid == null) {
            return;
        }

        int start = (number - 1) * apps_per_page;
        int end = int.min (start + apps_per_page, filtered_apps.size);

        int col = 0;
        int row = 0;

        for (int i = start; i < end; i++) {
            Backend.App app = filtered_apps.get (i);

            var app_button = new Widgets.AppButton (app);
            app_button.app_launched.connect (() => app_launched ());

            grid.get_child_at (col, row).destroy ();
            grid.attach (app_button, col, row, 1, 1);

            col++;
            if (col == (int) page.columns) {
                col = 0;
                row++;
            }
        }

        grid.show_all ();
        filled_pages.add (number);
    }

    // Public wrapper so navigation entry points outside this class (e.g.
    // the page-dot switcher, which scrolls the Paginator directly) can
    // make sure a page's AppButtons exist before it becomes visible.
    public void ensure_page_ready (int number) {
        ensure_page_filled (number);
    }

    // Opportunistically fills remaining pages one at a time during main-loop
    // idle time, so pages the user hasn't navigated to yet get a head start
    // on their (async) icon loads before they're actually needed.
    // ensure_page_filled ()'s filled_pages check makes this safe to overlap
    // with on-demand fills triggered by navigation.
    private void schedule_background_fill () {
        if (background_fill_source != 0) {
            GLib.Source.remove (background_fill_source);
            background_fill_source = 0;
        }

        int next_page = 2;

        background_fill_source = GLib.Idle.add (() => {
            if (next_page > total_page_count) {
                background_fill_source = 0;
                return GLib.Source.REMOVE;
            }

            ensure_page_filled (next_page);
            next_page++;

            return GLib.Source.CONTINUE;
        }, GLib.Priority.LOW);
    }

    private Gtk.Widget? get_widget_at (int column, int row) {
        var col = ((int)(column / page.columns)) + 1;

        if (col < 1 || col > total_page_count) {
            return null;
        }

        ensure_page_filled (col);

        var grid = grids.get (col);
        if (grid != null) {
            return grid.get_child_at (column - (int)page.columns * (col - 1), row) as Widgets.AppButton;
        } else {
            return null;
        }
    }

    private int get_n_pages () {
        return total_page_count;
    }

    private int get_current_page () {
        return (int) Math.round (paginator.position) + 1;
    }

    private Gtk.Widget get_page (int number) {
        assert (number > 0 && number <= get_n_pages ());

        ensure_page_filled (number);

        return paginator.get_children ().nth_data (number - 1);
    }

    public void go_to_next () {
        int page_number = get_current_page () + 1;
        if (page_number <= get_n_pages ()) {
            go_to_number (page_number);
        }
    }

    public void go_to_previous () {
        int page_number = get_current_page () - 1;
        if (page_number > 0) {
            go_to_number (page_number);
        }
    }

    public void go_to_last () {
        go_to_number (get_n_pages ());
    }

    public void go_to_number (int number) {
        paginator.scroll_to (get_page (number));
    }

    private bool set_focus (int column, int row) {
        var target_widget = get_widget_at (column, row);

        if (target_widget != null) {
            go_to_number (((int) (column / page.columns)) + 1);

            focused_column = column;
            focused_row = row;
            focused_widget = target_widget;

            focused_widget.grab_focus ();

            return true;
        }

        return false;
    }

    public override bool key_press_event (Gdk.EventKey event) {
        switch (event.keyval) {
            case Gdk.Key.Home:
            case Gdk.Key.KP_Home:
                go_to_number (1);
                return Gdk.EVENT_STOP;

            case Gdk.Key.Left:
            case Gdk.Key.KP_Left:
                if (get_style_context ().direction == Gtk.TextDirection.LTR) {
                    move_left (event);
                } else {
                    move_right (event);
                }

                return Gdk.EVENT_STOP;

            case Gdk.Key.Right:
            case Gdk.Key.KP_Right:
                if (get_style_context ().direction == Gtk.TextDirection.LTR) {
                    move_right (event);
                } else {
                    move_left (event);
                }

                return Gdk.EVENT_STOP;

            case Gdk.Key.Up:
            case Gdk.Key.KP_Up:
                if (set_focus (focused_column, focused_row - 1)) {
                    return Gdk.EVENT_STOP;
                }

                break;

            case Gdk.Key.Down:
            case Gdk.Key.KP_Down:
                set_focus (focused_column, focused_row + 1);
                return Gdk.EVENT_STOP;
        }

        return Gdk.EVENT_PROPAGATE;
    }

    private void move_left (Gdk.EventKey event) {
        if (event.state == Gdk.ModifierType.SHIFT_MASK) {
            go_to_previous ();
        } else {
            set_focus (focused_column - 1, focused_row);
        }
    }

    private void move_right (Gdk.EventKey event) {
        if (event.state == Gdk.ModifierType.SHIFT_MASK) {
            go_to_next ();
        } else {
            set_focus (focused_column + 1, focused_row);
        }
    }
}
