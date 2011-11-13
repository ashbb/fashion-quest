p 'loaded cli'

class Cli

  require 'pathname'

  include Parses_Commands
  include Handles_YAML_Files

  attr_accessor :prompt, :cursor, :standard_commands, :command_condition, :commands

  def initialize(params)

    require 'find'

    @prompt = '>'
    @cursor = '#'

    @output_stack      = params[:output_stack]
    @image_stack       = params[:image_stack]
    @game              = params[:game]
    @output_text       = params[:initial_text]

    @command_condition = params[:command_condition]

    @standard_commands = params[:standard_commands]

    @command_abbreviations = params[:command_abbreviations]
    @garbage_words         = params[:garbage_words]
    @global_synonyms       = params[:global_synonyms]

    if !@command_abbreviations
      load_abbreviations
    end

    if !@garbage_words
      load_garbage_words
    end

    if !@global_synonyms
      synonyms_file = "#{@game.path}parsing/global_synonyms.yaml"
      @global_synonyms = load_yaml_file(synonyms_file)
    end

    # add loading

    @message_text = ''
    @input_text   = ''

    initialize_commands

  end

  def load_abbreviations

    abbreviations_file = "#{@game.path}parsing/command_abbreviations.yaml"
    @command_abbreviations = load_yaml_file(abbreviations_file)

  end

  def load_garbage_words

    @garbage_words = load_yaml_file("#{@game.path}parsing/garbage_words.yaml")

  end

  def initialize_commands

    @command_history = []
    @command_index   = 0

    @commands = {}
    commands_loaded = 0

    command_paths = []

    standard_command_path = @game.app_base_path + '/standard_commands'

    # any standard commands listed in a game's config.yaml should be loaded
    if @standard_commands
      @standard_commands.each do |command|
        command_paths << (standard_command_path + '/' + command + '.yaml')
      end
    end

    # any commands contained in command directory (including subdirectories)
    # should be loaded
    Find.find("#{@game.path}commands") do |command_path|
      command_paths << command_path
    end rescue error "not found any files under #{@game.path}commands"

    # load commands
    command_paths.each do |command_path|

      if !FileTest.directory?(command_path) and (command_path.index('.yaml') or command_path.index('.yml'))

        # each command is stored in YAML as a hash
        command_data = load_yaml_file(command_path)

        # if no command data has loaded, try to load from standard commands directory
        if not command_data
          command_filename = Pathname.new(command_path).basename
          command_data = load_yaml_file(File.join(standard_command_path, command_filename))
        end

        if command_data

          # create command identifier based on filename
          command_id = command_path.split('/').last.sub('.yaml', '')

          # commands can access the game and image stack
          command = Command.new :id => command_id, :game => @game, :image_stack => @image_stack, :output_stack => @output_stack

          # commands have syntax and logic
          command.condition = command_data['condition']
          command.syntax    = command_data['syntax']
          command.logic     = command_data['logic']

          @commands[command.id] = command

          commands_loaded += 1
        else
          alert('Error: No command data found in ' + command_path + ' (and no command of same name found in standard_commands directory)')
        end

      end
    end

    if commands_loaded < 1

      error('No commands loaded.')
    end

  end

  # the flow of this function seems weird
  def keystroke(k)
    case

    # allow user to backspace
    when(k == 'BackSpace')
      @input_text = (@input_text.length > 1) ? @input_text[0..-2] : ''
    
    # allow user to cycle back in command history
    when(k == 'Up' and @command_index > 0)
      @command_index = @command_index - 1
      @input_text = @command_history[@command_index]
    
    # allow user to cycle forward in command history
    when(k == 'Down' and @command_index < @command_history.size)
      @command_index = @command_index + 1
      if @command_index == @command_history.size
        @input_text = ''
      else
        @input_text = @command_history[@command_index]
      end

    # add keystroke to input if it's not a special character
    when(k.class != Symbol and k != "\n")
      @input_text << k

    else
    end

    # update display prompt
    display_prompt(@input_text)

    # execute command
    if (k == :enter or k == "\n") && @input_text != ''
      if @input_text != 'load walkthrough'
        @command_history << @input_text
        @command_index = @command_history.size
      end
      issue_command(@input_text)
      display_prompt
    end

  end

  def reset

    @output_text = ''
    @output_stack.clear { }

    @command_history = []
    @command_index = 0

    initial_command('look')
    display_prompt

  end

  def restart

    if restarted = @game.restart
      reset
    else
      @input_text = ''
    end

    restarted

  end

  def issue_command(input_text, show_input = true)

    case input_text

      when 'restart'
        restart

      when 'clear'
        @output_text = ''
        @input_text =  ''

      when 'load'
        @game.load(ask_open_file)
        output_add("Game loaded.")
        @input_text = ''

      when 'save'
        @game.save(ask_open_file)
        output_add("Game saved.")
        @input_text = ''

      when 'save walkthrough'
        save_walkthrough

      when 'load walkthrough'
        load_walkthrough

      when 'save transcript'
        save_transcript

      when 'run script'
        run_script

      when 'compare to transcript'
        compare_to_transcript

      when 'vocab'
        show_vocabulary

      when 'vocabulary'
        show_vocabulary

      else

        output_add(@prompt + input_text) if show_input

        output = ''

        result = parse(input_text, @command_abbreviations, @garbage_words, @global_synonyms)

        # look for lines of output indicating subcommands should be called
        result.each_line do |line|
          # if the result of a command is prefixed with ">", redirect to another command
          if line[0] == ?>
            output << issue_command(line[1..-1], false)
          else
            output << line
          end
        end

        # execute turn logic if not executing a subcommand
        if show_input == true
          @message_text << @game.turn

          @output_text << output
          @input_text  = ''
        else
        # return subcommand output
          return output
        end

    end
  end

  def save_walkthrough

    if (filename = ask_save_file)

      save_data_as_yaml_file(@command_history[0...-1], filename)
      @output_text << "Walkthrough saved.\n"

    else
      alert('Aborted (or no free disk space).')
    end

    @input_text = ''

  end

  def load_walkthrough

    history_file = ask_open_file

    if history_file

      load_yaml_file(history_file).each do |command|

        issue_command(command)
        display_prompt
      end

    else

      @input_text = ''

    end

  end

  def save_transcript

    if (filename = ask_save_file)
      file = File.new(filename, "w")
      file.write(@output_text)
      file.close

      @output_text << "History saved.\n"
    else
      alert('Aborted (or no free disk space).')
    end

    @input_text = ''

  end

  def run_script

    if (filename = ask_open_file)

      File.open(filename, 'r') do |f|
        instance_eval(f.read)
      end

      @input_text = ''

    end
  end

  def compare_to_transcript

    if (filename = ask_open_file)
      transcript = ''
      f = File.open(filename, "r") 
      f.each_line do |line|
        transcript += line
      end

      if (transcript == @output_text)
        @output_text << "Pass!\n"
      else
        @output_text << "Fail!\n"
      end
      @input_text = ''
    end
  end

  def show_vocabulary

    vocab = []

    @commands.each do |id, command|
      vocab << id
    end

    vocab.sort.each do |command|
      output_add(command)
    end

    @input_text = ''

  end

  def display_prompt(input_text = '')

    output(@output_text, @prompt + input_text + @cursor)

    # add message to output text and clear
    @output_text += @message_text
    @message_text = ''

  end

  def output(output_text, input_text = '')
    # display output text, emphasize any messages, and show prompt
    $msg.text = output_text + $app.em(@message_text) + input_text + "\n" * 10
    @output_stack.swin.vscrollbar.value = $msg.height > 650 ? $msg.height - 650 : 0
  end

  def output_add(text, add_newline = true)

    optional_newline = add_newline ? "\n" : ''

    @output_text << text + optional_newline

  end

  def output_error
    return "I don't understand what you want from me.\n"
  end

  def initial_command(command)
    @output_text << issue_command('look', false)
    @input_text = ''
  end

end
