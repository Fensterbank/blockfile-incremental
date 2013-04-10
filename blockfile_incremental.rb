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

  def self.load_hashtable(filename)
    # Loading Hashtable
    stored_hash_table = nil
    if File.exist?("#{filename}_hashtable.dat")
      puts 'Loading stored hash table...'
      stored_hash_table = Hash.new

      open("#{filename}_hashtable.dat") do |hash_table|
        hash_table.read.each_line do |line|
          end_block, checksum = line.chomp.split(";")
          stored_hash_table[end_block] = checksum.strip
        end
      end
    end
    return stored_hash_table
  end

  public
  def self.incremental_backup(filename)
    time_begin = Time.now
    step_size_megaybtes = 5
    step_size = 1048576 * step_size_megaybtes

    stored_hash_table = BlockfileIncremental.load_hashtable (filename)

    puts "Processing #{filename}"
    puts "Size: #{File.size(filename)/1024/1024} MB"

    puts "\nReading..."
    @hash_table = Hash.new
    @directory_name = "#{filename}_#{DateTime.now.strftime('%Y%m%dT%H%M%S')}"
    Dir.mkdir(@directory_name)
    File.open(filename, 'rb') do | container |
      @processed_bytes = 0

      while not container.eof? do
        current_block = container.read(step_size)
        @processed_bytes += step_size
        if stored_hash_table.nil?
          BlockfileIncremental.write_block(current_block, nil)
        else
          BlockfileIncremental.write_block(current_block, stored_hash_table[@processed_bytes.to_s])
        end
      end
    end

    File.open("#{filename}_hashtable.dat", 'w') do | hash_file |
      @hash_table.each do | block_end, hash |
        hash_file.write("#{block_end};#{hash}\n")
      end
    end

    puts "Time passed: #{(Time.now - time_begin)} seconds"
  end

  def self.restore_backup(filename)
    time_begin = Time.now
    stored_hash_table = BlockfileIncremental.load_hashtable(filename)
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

BlockfileIncremental.incremental_backup('100M')
#BlockfileIncremental.restore_backup('100M')