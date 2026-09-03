// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
//
//  Copyright (C) 2011-2012 Giulio Collura
//  Copyright (C) 2014 Corentin Noël <tintou@mailoo.org>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

public class Slingshot.Widgets.Switcher : Gtk.Grid {
    public signal void on_paginator_changed ();

    private bool has_enough_children {
        get {
            return get_children ().length () > 1;
        }
    }

#if HANDY1
    private Hdy.Carousel paginator;
#else
    private Hdy.Paginator paginator;
#endif
    private unowned Slingshot.Widgets.Grid? grid_view;

    construct {
        halign = Gtk.Align.CENTER;
        orientation = Gtk.Orientation.HORIZONTAL;
        column_spacing = 3;
        can_focus = false;
        show_all ();
    }

#if HANDY1
    public void set_paginator (Hdy.Carousel paginator, Slingshot.Widgets.Grid? grid_view = null) {
#else
    public void set_paginator (Hdy.Paginator paginator, Slingshot.Widgets.Grid? grid_view = null) {
#endif
        if (this.paginator != null) {
            get_children ().foreach ((child) => {
                child.destroy ();
            });
        }

        this.paginator = paginator;
        this.grid_view = grid_view;
        foreach (var child in paginator.get_children ()) {
            add_child (child);
        }

        paginator.add.connect_after (add_child);
    }

    private void add_child (Gtk.Widget widget) {
        var button = new PageChecker (paginator, widget, grid_view);
        add (button);
    }

    public override void show () {
        base.show ();
        if (!has_enough_children) {
            hide ();
        }
    }

    public override void show_all () {
        base.show_all ();
        if (!has_enough_children) {
            hide ();
        }
    }
}
