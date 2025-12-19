# Open a log for the library
$OPENSTUDIO_LOG = OpenStudio::StringStreamLogSink.new
$OPENSTUDIO_LOG.setLogLevel(OpenStudio::Debug)

# Log the info, warning, and error messages to a runner.
#
# @param runner [OpenStudio::Measure::OSRunner] The Measure runner to add the messages to
# @param debug [Boolean] If true, include the debug messages in the log
# @param custom_exclusions [Array<String>] An array of custom strings to exclude from the log
def log_messages_to_runner(runner, debug = false, custom_exclusions: nil)
  log_message_exclusions = [
    'UseWeatherFile', # 'UseWeatherFile' is not yet a supported option for YearDescription
    'Skipping layer', # Annoying/bogus "Skipping layer" warnings
    'runmanager', # RunManager messages
    'setFileExtension', # .ddy extension unexpected
    'Translator', # Forward translator and geometry translator
    'Successive data points', # Successive data points (2004-Jan-31 to 2001-Feb-01, ending on line 753) are greater than 1 day apart in EPW file
    'has multiple parents', # Bogus errors about curves having multiple parents
    'does not have an Output', # Warning from EMS translation
    'Prior to OpenStudio 2.6.2, this field was returning a double, it now returns an Optional double' # Warning about OS API change
  ] + Array(custom_exclusions)

  $OPENSTUDIO_LOG.logMessages.each do |msg|
    # DLM: you can filter on log channel here for now
    if /openstudio.*/ =~ msg.logChannel # /openstudio\.model\..*/
      # Skip certain messages that are irrelevant/misleading
      next if log_message_exclusions.any? { |ex| msg.logMessage.include?(ex) }

      # Report the message in the correct way
      if msg.logLevel == OpenStudio::Info
        runner.registerInfo(msg.logMessage)
      elsif msg.logLevel == OpenStudio::Warn
        runner.registerWarning("[#{msg.logChannel}] #{msg.logMessage}")
      elsif msg.logLevel == OpenStudio::Error
        runner.registerError("[#{msg.logChannel}] #{msg.logMessage}")
      elsif debug && msg.logLevel == OpenStudio::Debug
        runner.registerInfo("DEBUG - #{msg.logMessage}")
      end
    end
  end
end

# A function that writes error message to log file and stop the execution.
#
# @param msg [String] error message
# @param log_path [String] the log file directory
# @param debug [Boolean] debug mode
def terminate_prm_write_log(msg, log_path, debug = false)
  OpenStudio.logFree(OpenStudio::Error, 'prm.log', msg)
  log_messages_to_file_prm("#{log_path}/prm.log", debug)
  raise msg
end

# A function to export log messages specific to PRM to a log file.
#
# @param file_path [String] the file path to the log file
# @param debug [Boolean] debug mode
# @return [Array] array of message strings
def log_messages_to_file_prm(file_path, debug = false)
  messages = []

  File.open(file_path, 'w') do |file|
    $OPENSTUDIO_LOG.logMessages.each do |msg|
      # only apply to prm
      if msg.logChannel.casecmp? 'prm.log'
        # Report the message in the correct way
        if msg.logLevel == OpenStudio::Info
          s = "[#{msg.logChannel}] INFO  #{msg.logMessage}"
          file.puts(s)
          messages << s
        elsif msg.logLevel == OpenStudio::Warn
          s = "[#{msg.logChannel}] WARN  #{msg.logMessage}"
          file.puts(s)
          messages << s
        elsif msg.logLevel == OpenStudio::Error
          s = "[#{msg.logChannel}] ERROR #{msg.logMessage}"
          file.puts(s)
          messages << s
        elsif msg.logLevel == OpenStudio::Debug && debug
          s = "[#{msg.logChannel}] DEBUG #{msg.logMessage}"
          file.puts(s)
          messages << s
        end
      end
    end
  end
  return messages
end

# Log the info, warning, and error messages to a file.
#
# runner @param [file_path] The path to the log file
# debug @param [Boolean] If true, include the debug messages in the log
# @return [Array<String>] The array of messages, which can be used elsewhere.
def log_messages_to_file(file_path, debug = false)
  messages = []

  File.open(file_path, 'w') do |file|
    $OPENSTUDIO_LOG.logMessages.each do |msg|
      # DLM: you can filter on log channel here for now
      if /openstudio.*/ =~ msg.logChannel # /openstudio\.model\..*/
        # Skip certain messages that are irrelevant/misleading
        next if msg.logMessage.include?('UseWeatherFile') || # 'UseWeatherFile' is not yet a supported option for YearDescription
                msg.logMessage.include?('Skipping layer') || # Annoying/bogus "Skipping layer" warnings
                msg.logChannel.include?('runmanager') || # RunManager messages
                msg.logChannel.include?('setFileExtension') || # .ddy extension unexpected
                msg.logChannel.include?('Translator') || # Forward translator and geometry translator
                msg.logMessage.include?('Successive data points') || # Successive data points (2004-Jan-31 to 2001-Feb-01, ending on line 753) are greater than 1 day apart in EPW file
                msg.logMessage.include?('has multiple parents') || # Bogus errors about curves having multiple parents
                msg.logMessage.include?('does not have an Output') || # Warning from EMS translation
                msg.logMessage.include?('Prior to OpenStudio 2.6.2, this field was returning a double, it now returns an Optional double') # Warning about OS API change

        # Report the message in the correct way
        if msg.logLevel == OpenStudio::Info
          s = "INFO  #{msg.logMessage}"
          file.puts(s)
          messages << s
        elsif msg.logLevel == OpenStudio::Warn
          s = "WARN  #{msg.logMessage}"
          file.puts(s)
          messages << s
        elsif msg.logLevel == OpenStudio::Error
          s = "ERROR #{msg.logMessage}"
          file.puts(s)
          messages << s
        elsif msg.logLevel == OpenStudio::Debug && debug
          s = "DEBUG #{msg.logMessage}"
          file.puts(s)
          messages << s
        end
      end
    end
  end

  return messages
end

# Get an array of all messages of a given type in the log
#
# @param log_type [OpenStudio::Class] type of messages to return from the log, e.g. OpenStudio::Error
# @return [Array<String>] An array of strings
def get_logs(log_type = OpenStudio::Error)
  errors = []

  $OPENSTUDIO_LOG.logMessages.each do |msg|
    if /openstudio.*/ =~ msg.logChannel
      # Skip certain messages that are irrelevant/misleading
      next if msg.logMessage.include?('UseWeatherFile') || # 'UseWeatherFile' is not yet a supported option for YearDescription
              msg.logMessage.include?('Skipping layer') || # Annoying/bogus "Skipping layer" warnings
              msg.logChannel.include?('runmanager') || # RunManager messages
              msg.logChannel.include?('setFileExtension') || # .ddy extension unexpected
              msg.logChannel.include?('Translator') || # Forward translator and geometry translator
              msg.logMessage.include?('Successive data points') || # Successive data points (2004-Jan-31 to 2001-Feb-01, ending on line 753) are greater than 1 day apart in EPW file
              msg.logMessage.include?('has multiple parents') || # Bogus errors about curves having multiple parents
              msg.logMessage.include?('does not have an Output') || # Warning from EMS translation
              msg.logMessage.include?('Prior to OpenStudio 2.6.2, this field was returning a double, it now returns an Optional double') # Warning about OS API change

      # Only fail on the errors
      if msg.logLevel == log_type
        errors << "[#{msg.logChannel}] #{msg.logMessage}"
      end
    end
  end

  return errors
end

# resets the log
def reset_log
  $OPENSTUDIO_LOG.resetStringStream
end
