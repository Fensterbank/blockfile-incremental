=begin
BLOCKFILE-INCREMENTAL (https://github.com/Fensterbank/blockfile-incremental)

Copyright (C) Frédéric Bolvin  | https://github.com/Fensterbank

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.
                                             *
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public
License along with this program.
If not, see http://www.gnu.org/licenses/gpl-3.0.html.
=end
require 'date'
require 'digest/sha2'
require 'yaml'

class Blockfile
  private

  def self.print_percentage
    processed_megabytes = @processed_bytes/1024.0/1024.0
    percentage = ((processed_megabytes / @whole_size)*100)
    if (percentage-@last_percentage) > 5
      puts "#{percentage.round(1)} % (#{processed_megabytes.round(0)} MB) processed"
      @last_percentage = percentage
    end
  end

  def self.write_block (current_block,stored_hash)
    written = false
    print_percentage
    block_hash = Digest::SHA256.new << current_block
    if !stored_hash.nil? and !block_hash.to_s.eql?(stored_hash)
      File.open(File.join(@directory_name,block_hash.to_s), 'w') do | block_file |
        block_file.write(current_block)
        written = true
      end
    elsif stored_hash.nil?
      File.open(File.join(@directory_name,block_hash.to_s), 'w') do | block_file |
        block_file.write(current_block)
        written = true
      end
    end

    @hash_table[@processed_bytes] = block_hash.to_s
    return written
  end

  def self.load_hashtable(target_path,mode,restoring)
    # Loading Hashtable

    stored_hash_table = nil

    directories = Dir.entries(target_path).select {|entry| File.directory? File.join(target_path,entry) and !(entry =='.' || entry == '..') }.sort

    if (!directories.last.nil? && File.exist?(File.join(target_path, directories.last, 'hashtable_latest.csv'))) && (restoring || mode == 'incremental')
      file_path = File.join(target_path, directories.last, 'hashtable_latest.csv')
      @restore_backup_date = DateTime.parse(directories.last.split('_').first)
    else
      file_path = find_file('hashtable_initial.csv', directories, target_path)
      unless file_path.nil?
        @restore_backup_date = DateTime.parse(File.split(file_path).first.split(File::Separator).last)
      end
    end

    if !file_path.nil? && File.exist?(file_path)
      Writer.output 'Loading stored hash table...'
      stored_hash_table = Hash.new
      open(file_path) do |hash_table|
        hash_table.read.each_line do |line|
          end_block, checksum = line.chomp.split(';')
          stored_hash_table[end_block] = checksum.strip
        end
      end
    else
      Writer.info 'No hash table found. Starting a new full backup...' unless restoring
      @initial_backup = true
    end
    return stored_hash_table
  end

  def self.write_hashtable(initial)
    if initial
      Writer.info('Writing initial hashtable...')
      filename = 'hashtable_initial.csv'
    else
      Writer.info('Writing new hashtable...')
      filename = 'hashtable_latest.csv'
    end

    file_path = File.join(@directory_name, filename)
    File.open(file_path, 'w') do | hash_file |
      @hash_table.each do | block_end, hash |
        hash_file.write("#{block_end};#{hash}\n")
      end
    end
    return File.size(file_path)
  end

  def self.process_file(file_path, target_path, stored_hash_table, step_size)
    puts "Processing file '#{file_path}'"
    @whole_size = File.size(file_path)/1024.0/1024.0

    puts "Size: #{@whole_size} MB"

    puts "\nReading..."
    @hash_table = Hash.new

    if @initial_backup
      @directory_name = File.join(target_path,DateTime.now.strftime('%Y%m%dT%H%M%S') + '_initial')
    else
      @directory_name = File.join(target_path,DateTime.now.strftime('%Y%m%dT%H%M%S'))
    end

    Dir.mkdir(@directory_name)

    written_bytes = 0;
    File.open(file_path, 'rb') do | container |
      @processed_bytes = 0

      until container.eof? do
        current_block = container.read(step_size)
        @processed_bytes += step_size
        if stored_hash_table.nil?
          written_bytes += current_block.length if Blockfile.write_block(current_block, nil)
        else
          written_bytes += current_block.length if Blockfile.write_block(current_block, stored_hash_table[@processed_bytes.to_s])
        end
      end
    end
    return written_bytes
  end

  public
  # Backup the Container with given configuration
  def self.backup(configuration)
    Writer.info("Starting #{configuration['mode']} backup...")

    if configuration['target-path'].include? ' '
      Writer.warning('Spaces are not allowed in target path. Spaces will be replaced by underscore!')
      configuration['target-path'] = configuration['target-path'].tr(' ', '_')
    end

    time_begin = Time.now
    @last_percentage = 0.0
    filename = configuration['container']

    unless File.exist?(filename)
      Writer.error("Container file '#{filename}' not found!")
      return
    end

    if configuration['truecrypt']['enabled'] && configuration['truecrypt']['unmount']
      Writer.info('Trying to unmount truecrypt volume, if necessary...')
      Writer.warning 'Volume was not mounted or an error occured!' unless system("#{configuration['truecrypt']['binary']} -d #{configuration['container']}").to_s
    end
                                                                                                              012
    target_path = configuration['target-path']
    Dir.mkdir(target_path) unless Dir.exist?(target_path)

    step_size_megabytes = configuration['block-size']
    step_size = 1048576 * step_size_megabytes

    stored_hash_table = Blockfile.load_hashtable(target_path, configuration['mode'], false)

    written_bytes = Blockfile.process_file(filename, target_path, stored_hash_table, step_size)
    if @initial_backup
      written_bytes += Blockfile.write_hashtable(true)
    else
      written_bytes += Blockfile.write_hashtable(false)
    end

    # Pack the container to archive file
    if configuration['packing']['enabled'] && configuration['packing']['format'] == 'tar'
      Writer.info('Packing created folder into tar package...')
      system("tar -cvf #{@directory_name}.tar #{File.join(@directory_name)+File::SEPARATOR}")
    end

    Writer.success("Finished! Time passed: #{(Time.now - time_begin).round(2)} seconds")
    Writer.success("#{(written_bytes/1024.0/1024.0).round(2)} MB of new backup data written.")
  end

  def self.find_file(file_name, directories, target_path)
    directories.each do | dir |
      full_path = File.join(target_path, dir,file_name)
      if File.exist?(full_path)
        return full_path
      end
    end
    return nil
  end

  def self.restore_backup(configuration, restore_path)
    time_begin = Time.now

    if configuration['target-path'].include? ' '
      Writer.warning('Spaces are not allowed in target path. Spaces will be replaced by underscore!')
      configuration['target-path'] = configuration['target-path'].tr(' ', '_')
    end

    target_path = configuration['target-path']
    if Dir.exist?(target_path)
      stored_hash_table = Blockfile.load_hashtable(target_path,configuration['mode'], true)

      if stored_hash_table.nil?
        Writer.error 'Hashtable not found!'
      else
        Writer.output "Restoring container file from last backup (#{@restore_backup_date.strftime('%F %T')})..."
        directories = Dir.entries(target_path).select {|entry| File.directory? File.join(target_path,entry) and !(entry =='.' || entry == '..') }
        if directories.length==0
          Writer.error "No backup directories found in path '#{target_path}'!"
          return
        end

        count = stored_hash_table.length

        if restore_path.nil?
          restore_path = configuration['container']
        end

        if File.exist?(restore_path)
          restored_filename = restore_path + '_restored.tc'
          Writer.info "Container file '#{restore_path}' already exists."
        else
          restored_filename = restore_path
        end
        Writer.info "Restored file will be named '#{restored_filename}'"

        Writer.output("Checking existence of all #{stored_hash_table.length} files...")
        block_files = Array.new
        stored_hash_table.each do | block_end, hash |
          found_file = find_file(hash, directories, target_path)
          if found_file.nil?
            Writer.error("File '#{hash}' is missing. Backup could not be restored!")
            return
          else
            block_files.push found_file
          end
        end

        Writer.output 'All needed files found...'

        File.open(restored_filename, 'w') do | container |
          block_files.each_with_index do | file_name, index |
            container.write(File.read(file_name))
            puts "#{index+1} of #{count} files processed..."
          end
        end
      end
    else
      Writer.error ("Folder #{target_path} does not exist!")
      return
    end
    Writer.success "Finished! Time passed: #{(Time.now - time_begin).round(2)} seconds"
  end
end

class Writer
  private
  def self.black(s) "\033[30m#{s}\033[0m" end
  def self.red(s) "\033[31m#{s}\033[0m" end
  def self.green(s) "\033[32m#{s}\033[0m" end
  def self.brown(s) "\033[33m#{s}\033[0m" end
  def self.blue(s) "\033[34m#{s}\033[0m" end
  def self.magenta(s) "\033[35m#{s}\033[0m" end
  def self.cyan(s) "\033[36m#{s}\033[0m" end
  def self.gray(s) "\033[37m#{s}\033[0m" end

  public
  def self.error(message)
    puts red("Error: #{message}")
  end

  def self.info(message)
    puts cyan(message)
  end

  def self.success(message)
    puts green(message)
  end

  def self.warning(message)
    puts brown(message)
  end

  def self.output(message)
    puts message
  end

  def self.bold(message)
     puts "\033[1m#{message}\033[22m"
  end
end


Writer.bold "BlockFile-Incremental v 0.2.1\n\n"
if ARGV.length >= 1
  filename = ARGV[1]
  action = ARGV[0]

  configuration = nil
  if ARGV.length >= 2
    if File.exist?(filename)
      configuration = YAML.load(File.read(filename))
    else
      Writer.error("File #{filename} does not exist!")
    end
  end

  case action
    when 'backup'
      if configuration.nil?
        Writer.error('Invalid filename or second argument (filename to config file) missing!')
      else
        if configuration['mode'] == 'incremental' || configuration['mode'] == 'differential'
          Blockfile.backup(configuration)
        else
          Writer.error("Unknown backup mode '#{configuration['mode']}'. Please select 'incremental' or 'differential'")
        end
      end
    when 'restore'
      if configuration.nil?
        Writer.error('Invalid filename or second argument (filename to config file) missing!')
      else
        restore_path = ARGV[2]
        Blockfile.restore_backup(configuration, restore_path)
      end
    when 'example'
      Writer.info 'Usage Examples:'
      Writer.info 'blockfile_incremental.rb backup config.yml'
      Writer.info 'blockfile_incremental.rb restore config.yml'
      Writer.info 'blockfile_incremental.rb restore config.yml /tmp/restorefile.dat'
    else
      Writer.error("Unknown argument '#{action}'. Allowed arguments: backup, restore, example")
  end
else
  Writer.error("Please pass command ('backup' or 'restore') and config file as command line arguments!")
end