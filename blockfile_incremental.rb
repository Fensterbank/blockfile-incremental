require 'date'
require 'digest/sha2'

class BlockfileIncremental
  private
  def self.write_block (current_block,stored_hash)
    puts "#{@processed_bytes/1024/1024} MB processed"
    block_hash = Digest::SHA256.new << current_block
    if !stored_hash.nil? and !block_hash.to_s.eql?(stored_hash)
      File.open(File.join(@directory_name,block_hash.to_s), 'w') do | block_file |
        block_file.write(current_block)
      end
    elsif stored_hash.nil?
      File.open(File.join(@directory_name,block_hash.to_s), 'w') do | block_file |
        block_file.write(current_block)
      end
    end
    @hash_table[@processed_bytes] = block_hash.to_s
  end

  def self.load_hashtable
    # Loading Hashtable
    stored_hash_table = nil
    if File.exist?('hashtable.dat')
      puts 'Loading stored hash table...'
      stored_hash_table = Hash.new

      open('hashtable.dat') do |hash_table|
        hash_table.read.each_line do |line|
          end_block, checksum = line.chomp.split(";")
          stored_hash_table[end_block] = checksum.strip
        end
      end
    end
    return stored_hash_table
  end

  public
  def self.incremental_backup
    time_begin = Time.now
    step_size_megaybtes = 5
    step_size = 1048576 * step_size_megaybtes
    filename = '30M'

    stored_hash_table = BlockfileIncremental.load_hashtable

    puts "Processing #{filename}"
    puts "Size: #{File.size(filename)/1024/1024} MB"

    puts "\nReading..."
    @hash_table = Hash.new
    @directory_name = DateTime.now.strftime('%Y%m%dT%H%M%S%z')
    Dir.mkdir(@directory_name)
    File.open(filename) do | container |
      current_block = String.new
      @processed_bytes = 0
      index = 0

      container.each_byte do | byte |
        @processed_bytes += 1
        index += 1
        current_block << byte

        if index == step_size
          if stored_hash_table.nil?
            BlockfileIncremental.write_block(current_block, nil)
          else
            BlockfileIncremental.write_block(current_block, stored_hash_table[@processed_bytes.to_s])
          end
          index = 0
          current_block = String.new
        end
      end

      # Writing the rest
      if index > 0
        if stored_hash_table.nil?
          BlockfileIncremental.write_block(current_block, nil)
        else
          BlockfileIncremental.write_block(current_block, stored_hash_table[@processed_bytes.to_s])
        end
      end
    end


    # Writing
    puts "\nWrite hashtable..."
    File.open('hashtable.dat', 'w') do | hash_file |
      @hash_table.each do | block_end, hash |
        hash_file.write("#{block_end};#{hash}\n")
      end
    end

    puts "Time passed: #{(Time.now - time_begin)} seconds"
  end

  def self.restore_backup
    time_begin = Time.now
    stored_hash_table = BlockfileIncremental.load_hashtable
    unless stored_hash_table.nil?
      directories = Dir.entries('.').select {|entry| File.directory? File.join('.',entry) and !(entry =='.' || entry == '..') }

      puts 'Restore container file from incremental backups...'
      count = stored_hash_table.length
      File.open('restored', 'w') do | container |
        i = 0
        stored_hash_table.each do | block_end, hash |
          directories.each do | dir |
            if File.exist?(File.join(dir,hash))
              i += 1
              container.write(File.read(File.join(dir,hash)))
              puts "#{i} of #{count} Files processed..."
              break
            end
          end
        end
      end
    else
      puts 'Hashtable not found!'
    end
    puts "Time passed: #{(Time.now - time_begin)} seconds"
  end
end

#TruecryptIncremental.incremental_backup
BlockfileIncremental.restore_backup