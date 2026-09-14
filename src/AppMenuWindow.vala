/*
 * This file is part of budgie-extras (Applications Menu applet)
 *
 * Copyright 2019-2026 Ubuntu Budgie Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

namespace AppMenuApplet {
	/**
	 * Hosts the Slingshot view in its own toplevel layer-shell surface
	 * instead of a Budgie.Popover.
	 *
	 * On Wayland a popover is a subsurface of its parent (the panel), and
	 * only gets keyboard input while the panel itself is focused - which a
	 * keybinding can't do. So, as with BudgieMenuWindow in budgie-desktop
	 * (see commits 0e3ab119 and a6b2a31a upstream), the menu is made its
	 * own layer-shell window with custom positioning and an overlaid arrow
	 * standing in for the popover's tail.
	 */
	public class AppMenuWindow : Gtk.Window {
		private static Gtk.CssProvider css_provider;

		private Gtk.Overlay outer_layout;
		private MenuArrow arrow;

		public Slingshot.SlingshotView view { get; private set; }

		// The launcher button the menu is aligned against
		private unowned Gtk.Widget? launcher;

		// True once we have had keyboard focus since show(), so the
		// unfocused state right after showing isn't mistaken for losing it
		private bool focus_granted = false;

		// Losing focus while the pointer is over the menu isn't a click outside
		private bool pointer_inside = false;

		static construct {
			css_provider = new Gtk.CssProvider();
			css_provider.load_from_resource("/io/elementary/desktop/wingpanel/applications-menu/AppMenuWindow.css");
			// Applies to the window, the view (.appmenu-body) and the arrow
			// (.appmenu-arrow), which are three separate widgets
			Gtk.StyleContext.add_provider_for_screen(
				Gdk.Screen.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
		}

		public AppMenuWindow(Slingshot.SlingshotView view, Gtk.Widget? launcher) {
			Object(type: Gtk.WindowType.TOPLEVEL);
			this.view = view;
			this.launcher = launcher;

			//this.get_style_context().add_class("appmenu-window");
			this.get_style_context().add_class("budgie-menu-window");
			this.decorated = false;
			this.resizable = false;
			this.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK);

			// A popover only gets keyboard input while the panel is focused,
			// and a keybinding can't focus the panel. So the menu is its own
			// layer surface.
			if (GtkLayerShell.is_supported()) {
				GtkLayerShell.init_for_window(this);
				GtkLayerShell.set_namespace(this, "appmenu");
				GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP);
				GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND);
			}

			// Transparent window so the arrow can stick out past the body
			this.app_paintable = true;
			Gdk.Visual? visual = this.get_screen().get_rgba_visual();
			if (visual != null) {
				this.set_visual(visual);
			}

			//this.view.get_style_context().add_class("appmenu-body");
			this.view.get_style_context().add_class("budgie-menu");

			this.arrow = new MenuArrow();

			// The arrow reaches back over the body's border, so it can't be
			// a sibling in a box. The body carries a margin on the
			// panel-facing side for the arrow to sit in.
			this.outer_layout = new Gtk.Overlay();
			this.outer_layout.add(this.view);
			this.outer_layout.add_overlay(this.arrow);
			this.outer_layout.set_overlay_pass_through(this.arrow, true);
			this.add(this.outer_layout);

			// Close on anything that used to just close the popover
			this.view.close_indicator.connect(this.hide);

			this.map.connect(on_map);
			this.notify["is-active"].connect(on_active_changed);
			this.enter_notify_event.connect(on_enter_notify);
			this.leave_notify_event.connect(on_leave_notify);
			this.key_release_event.connect(on_key_release);

			// Respects no_show_all, so hidden children stay hidden
			this.outer_layout.show_all();
		}

		private bool on_key_release(Gdk.EventKey e) {
			if (e.keyval == Gdk.Key.Escape) {
				this.hide();
			}
			return Gdk.EVENT_PROPAGATE;
		}

		// The entry can only take focus once the surface is up
		private void on_map() {
			Idle.add(focus_search_entry);
		}

		private bool focus_search_entry() {
			this.view.search_entry.grab_focus();
			return Source.REMOVE;
		}

		// Losing keyboard focus is the layer-surface version of a click
		// outside, unless the pointer is still over the menu
		private void on_active_changed(Object sender, ParamSpec pspec) {
			if (this.is_active) {
				this.focus_granted = true;
			} else if (this.focus_granted && this.visible && !this.pointer_inside) {
				this.hide();
			}
		}

		// INFERIOR crossings are into our own children, not out of the window
		private bool on_enter_notify(Gdk.EventCrossing event) {
			if (event.detail != Gdk.NotifyType.INFERIOR) {
				this.pointer_inside = true;
			}
			return Gdk.EVENT_PROPAGATE;
		}

		private bool on_leave_notify(Gdk.EventCrossing event) {
			if (event.detail != Gdk.NotifyType.INFERIOR) {
				this.pointer_inside = false;
			}
			return Gdk.EVENT_PROPAGATE;
		}

		/**
		 * Align the menu with the launcher on the panel's edge, then show it.
		 */
		public void present_menu(Budgie.PanelPosition position) {
			this.set_geometry(position);
			this.focus_granted = false;
			this.pointer_inside = false;
			this.view.show_slingshot();
			this.show();
		}

		/**
		 * Layer-shell surfaces can only be placed against output edges, so
		 * the menu is anchored to the panel's edge and pushed along it by a
		 * margin that centers it on the launcher.
		 */
		private void set_geometry(Budgie.PanelPosition position) {
			if (!GtkLayerShell.is_supported()) {
				return;
			}

			Gtk.Window? panel = this.launcher != null ? this.launcher.get_toplevel() as Gtk.Window : null;

			// Get the monitor that the panel is on
			Gdk.Monitor? monitor = null;
			if (panel != null && GtkLayerShell.is_layer_window(panel)) {
				monitor = GtkLayerShell.get_monitor(panel);
				if (monitor != null) { // Set the window (this) to be on the same monitor as the panel
					GtkLayerShell.set_monitor(this, monitor);
				}
			}

			// Clear stale anchors; the panel may have moved since the last show
			GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, false);
			GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, false);
			GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, false);
			GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, false);

			bool vertical = (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT);

			int monitor_extent = 0;
			if (monitor != null) {
				Gdk.Rectangle geometry = monitor.get_geometry();
				monitor_extent = vertical ? geometry.height : geometry.width;
			}

			// Where the launcher sits along the panel and how big it is. The
			// panel starts at the monitor edge, so panel coordinates are
			// monitor coordinates.
			int launcher_offset = 0;
			int launcher_extent = 0;
			if (this.launcher != null) {
				int lx = 0;
				int ly = 0;
				if (panel != null && this.launcher.translate_coordinates(panel, 0, 0, out lx, out ly)) {
					launcher_offset = vertical ? ly : lx;
				}

				Gtk.Allocation launcher_alloc;
				this.launcher.get_allocation(out launcher_alloc);
				launcher_extent = vertical ? launcher_alloc.height : launcher_alloc.width;
			}

			// A dock-mode panel is shorter than the monitor and centered on
			// it by the compositor, so it doesn't start at the monitor edge.
			// Zero for a full panel.
			if (panel != null && monitor_extent > 0) {
				int panel_extent = vertical ? panel.get_allocated_height() : panel.get_allocated_width();
				int panel_start = (monitor_extent - panel_extent) / 2;
				if (panel_start > 0) {
					launcher_offset += panel_start;
				}
			}

			int menu_min = 0;
			int menu_nat = 0;
			if (vertical) {
				this.view.get_preferred_height(out menu_min, out menu_nat);
			} else {
				this.view.get_preferred_width(out menu_min, out menu_nat);
			}
			// Fallback if the body has no size yet
			if (menu_nat <= 0) {
				menu_nat = launcher_extent;
			}

			// Keep the menu on the monitor; the arrow slides to stay on the launcher
			int margin = launcher_offset + (launcher_extent - menu_nat) / 2;
			if (monitor_extent > 0) {
				int max_margin = monitor_extent - menu_nat;
				if (max_margin < 0) max_margin = 0;
				if (margin > max_margin) margin = max_margin;
			}
			if (margin < 0) margin = 0;

			this.arrange_arrow(position, vertical, launcher_offset + launcher_extent / 2 - margin, menu_nat);

			switch (position) {
				case Budgie.PanelPosition.TOP:
					GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
					GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
					GtkLayerShell.set_margin(this, GtkLayerShell.Edge.LEFT, margin);
					break;
				case Budgie.PanelPosition.LEFT:
					GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
					GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
					GtkLayerShell.set_margin(this, GtkLayerShell.Edge.TOP, margin);
					break;
				case Budgie.PanelPosition.RIGHT:
					GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
					GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
					GtkLayerShell.set_margin(this, GtkLayerShell.Edge.TOP, margin);
					break;
				case Budgie.PanelPosition.BOTTOM:
				default:
					GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
					GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
					GtkLayerShell.set_margin(this, GtkLayerShell.Edge.LEFT, margin);
					break;
			}
		}

		/**
		 * Put the arrow on the panel-facing side of the body, pointing at
		 * the launcher.
		 */
		private void arrange_arrow(Budgie.PanelPosition position, bool vertical, int launcher_center, int menu_nat) {
			this.arrow.position = position;

			// Leave room for the arrow on the panel-facing side, and tell it
			// how far back over the body's border it has to reach to cover
			// the join
			Gtk.StyleContext body_style = this.view.get_style_context();
			Gtk.Border body_border = body_style.get_border(body_style.get_state());

			// Clear the room left for a previous panel position
			this.view.margin_top = 0;
			this.view.margin_bottom = 0;
			this.view.margin_start = 0;
			this.view.margin_end = 0;

			switch (position) {
				case Budgie.PanelPosition.TOP:
					this.view.margin_top = MenuArrow.ARROW_DEPTH;
					this.arrow.overlap = body_border.top;
					break;
				case Budgie.PanelPosition.LEFT:
					this.view.margin_start = MenuArrow.ARROW_DEPTH;
					this.arrow.overlap = body_border.left;
					break;
				case Budgie.PanelPosition.RIGHT:
					this.view.margin_end = MenuArrow.ARROW_DEPTH;
					this.arrow.overlap = body_border.right;
					break;
				case Budgie.PanelPosition.BOTTOM:
				default:
					this.view.margin_bottom = MenuArrow.ARROW_DEPTH;
					this.arrow.overlap = body_border.bottom;
					break;
			}

			// The menu may have been shifted to stay on the monitor; keep
			// the arrow within the body
			int offset = launcher_center - MenuArrow.ARROW_BREADTH / 2;
			int max_offset = menu_nat - MenuArrow.ARROW_BREADTH;
			if (max_offset < 0) max_offset = 0;
			if (offset > max_offset) offset = max_offset;
			if (offset < 0) offset = 0;

			// Clear the margin left by a previous panel position
			this.arrow.margin_top = 0;
			this.arrow.margin_start = 0;
			if (vertical) {
				this.arrow.halign = position == Budgie.PanelPosition.LEFT ? Gtk.Align.START : Gtk.Align.END;
				this.arrow.valign = Gtk.Align.START;
				this.arrow.margin_top = offset;
			} else {
				this.arrow.halign = Gtk.Align.START;
				this.arrow.valign = position == Budgie.PanelPosition.TOP ? Gtk.Align.START : Gtk.Align.END;
				this.arrow.margin_start = offset;
			}

			// The arrow's size request depends on position, so it must be renegotiated
			this.arrow.queue_resize();
		}
	}
}
