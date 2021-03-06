=begin header

  labels.rb - a part of testgtk.c rewritten in ruby-gtk

=end

require 'sample'

class LabelSample < SampleWindow
  def initialize
    super("Label")
    border_width(5)

    vbox = Gtk::VBox::new(false, 5)
    vbox.show
    hbox = Gtk::HBox::new(false, 5)
    hbox.show
    hbox.pack_start(vbox, false, false, 0)

    create_frame_with_label("Normal Label",
			    "This is a Normal label",
			    vbox)
    create_frame_with_label("Multi-line Label",
			    "This is a Multi-line label.\nSecond line\nThird line",
			    vbox)
    create_frame_with_label("Left Justified Label",
			    "This is a Left-Justified\nMulti-line label.\nThird      line",
			    vbox) do |label|
      label.jtype = Gtk::JUSTIFY_LEFT
    end
    create_frame_with_label("Right Justified Label",
			    "This is a Right-Justified\nMulti-line label.\nFourth line, (j/k)",
			    vbox) do |label|
      label.jtype = Gtk::JUSTIFY_RIGHT
    end

    vbox = Gtk::VBox::new(false, 5)
    vbox.show
    hbox.pack_start(vbox, false, false, 0)

    create_frame_with_label("Line wrapped label",
			    "This is an example of a line-wrapped label.  It should not be taking up the entire             width allocated to it, but automatically wraps the words to fit.  The time has come, for all good men, to come to the aid of their party.  The sixth sheik's six sheep's sick.\n     It supports multiple paragraphs correctly, and  correctly   adds many          extra  spaces. ",
			    vbox) do |label|
      label.set_line_wrap(true)
    end
    create_frame_with_label("Filled, wrapped label",
     "This is an example of a line-wrapped, filled label.  It should be taking up the entire              width allocated to it.  Here is a seneance to prove my point.  Here is another sentence. Here comes the sun, do de do de do.\n    This is a new paragraph.\n    This is another newer, longer, better paragraph.  It is coming to an end, unfortunately.",
			    vbox) do |label|
      label.jtype = Gtk::JUSTIFY_FILL
      label.set_line_wrap(true)
    end
    create_frame_with_label("Underlined label",
			    "This label is underlined!\nThis one is underlined in 日本語の入用quite a funky fashion",
			    vbox) do |label|
      label.jtype = Gtk::JUSTIFY_LEFT
      label.set_pattern("_________________________ _ _________ _ _____ _ __ __  ___ ____ _____")
    end

    add(hbox)
  end

  def create_frame_with_label(title, label_str, vbox)
    frame = Gtk::Frame::new(title)
    frame.show
    label = Gtk::Label::new(label_str)
    label.show
    yield(label) if iterator?
    frame.add(label)
    vbox.pack_start(frame, false, false, 0)
  end

  private :create_frame_with_label
end
