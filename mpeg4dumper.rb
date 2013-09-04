#
# Provided by wmspanel.com team
# Author: Alex Pokotilo
# Contact: support@wmspanel.com
#

# ISO/IEC 14496-12:2008 implementation

class IsoBaseMediaFile
  class InvalidFileException < Exception
  end

  class Box
    attr_accessor :file, :offset, :size, :type, :parent

    def getInt8
      buffer =  (@file.read 1).unpack('C*')
      raise InvalidFileException if buffer.length != 1
      @offset+=1
      return  buffer[0]
    end

    def getInt16
      buffer =  (@file.read 2).unpack('C*')
      raise InvalidFileException if buffer.length != 2
      @offset+=2
      return  0x100 * buffer[0] + buffer[1]
    end

    def getInt24
      buffer =  (@file.read 3).unpack('C*')
      raise InvalidFileException if buffer.length != 3
      @offset+=3
      return  0x10000  * buffer[0] + 0x100 * buffer[1] + buffer[2]
    end

    def getInt32
      buffer =  (@file.read 4).unpack('C*')
      raise InvalidFileException if buffer.length != 4
      @offset+=4
      return  0x1000000 * buffer[0] + 0x10000  * buffer[1] + 0x100 * buffer[2] + buffer[3]
    end

    def getInt64
      return (getInt32() << 32) + getInt32()
    end

    def getInt32Array n
      result = []
      n.times do
        result << getInt32
      end
      result
    end

    def get32BitString
      buffer = @file.read 4
      raise InvalidFileException if buffer.length != 4
      @offset+=4
      return buffer
    end
    def getFixedSizeString n
      len = (@file.read 1).unpack('C*')
      raise InvalidFileException if len.length != 1
      len = len[0]
      raise InvalidFileException if len > n - 1

      buffer = (len > 0) ? @file.read(len) : nil
      if len + 1 < 32
        @file.seek(32 - (len + 1) , IO::SEEK_CUR)
      end
      @offset+= n
      return buffer
    end

    def getByteArray n
      buffer =  (@file.read n).unpack('C*')
      raise InvalidFileException if buffer.length != n
      @offset+=n
      return buffer
    end

    def skipNBytes bytes2skip
      if @size > @offset + bytes2skip
        @file.seek(bytes2skip, IO::SEEK_CUR)
      elsif  @size < @offset + bytes2skip
        raise InvalidFileException
      end
      @offset += bytes2skip
    end

    def skipBox
      if @size > 0
        if @size > @offset
          @file.seek(@size - @offset, IO::SEEK_CUR)
        elsif  @size < @offset
          raise InvalidFileException
        end
      else
        @file.seek(0, IO::SEEK_END) # lets move to the end of the file
      end
      @offset = @size
    end

    def initBaseParams
      @size = getInt32()

      if @size == 1
        @size = getInt64() # box size is 64-bit in case size ==1
      end

      @type = get32BitString()
    end

    def initialize parent, arg
      @parent = parent

      if arg.is_a? File
        @offset = 0
        @file = arg
        initBaseParams()
      else
        @offset = arg.offset
        @size   = arg.size
        @file   = arg.file
        @type   = arg.type
      end
    end

    def load
      skipBox
    end
  end

  class FullBox < Box
    attr_accessor :flags

    def initialize parent, arg
      super parent, arg
      @version = getInt8()
      @flags   = getInt24()
    end
  end

  class FileTypeBox < Box
    def load
      @major_brand   = get32BitString()
      @minor_version = getInt32()
      @compatible_brands = []
      while @size > @offset && !@file.eof?
        @compatible_brands << get32BitString()
      end

      raise InvalidFileException if @size != @offset
    end
  end

  class MovieHeaderBox < FullBox
    attr_accessor :creation_time, :modification_time, :timescale, :duration

    def load
      if @version == 1
        @creation_time = getInt64()
        @modification_time = getInt64()
        @timescale = getInt32()
        @duration = getInt64()
      else
        @creation_time = getInt32()
        @modification_time = getInt32()
        @timescale = getInt32()
        @duration = getInt32()
      end
      skipBox
    end
  end

  class TrackHeaderBox < FullBox
    attr_accessor :track_ID, :duration, :width, :height

    def load

      if @version == 1
        @creation_time = getInt64()
        @modification_time = getInt64()
        @track_ID = getInt32()
        skipNBytes(4) # const unsigned int(32) reserved = 0;
        @duration = getInt64()
      else
        @creation_time = getInt32()
        @modification_time = getInt32()
        @track_ID = getInt32()
        skipNBytes(4) # const unsigned int(32) reserved = 0;
        @duration = getInt32()
      end

      skipNBytes(8 + # const unsigned int(32)[2] reserved = 0;
                 2 + # template int(16) layer = 0;
                 2 + # template int(16) alternate_group = 0
                 2 + # template int(16) volume = {if track_is_audio 0x0100 else 0};
                 2 + # const unsigned int(16) reserved = 0;
                 9 * 4  # template int(32)[9] matrix= { 0x00010000,0,0,0,0x00010000,0,0,0,0x40000000 };
      )

      # width and height are 16.16 values
      @width  = getInt32() / 0x10000
      @height = getInt32() / 0x10000

      skipBox
    end
  end

  class MediaHeaderBox < FullBox
    attr_accessor :lang

    def load
      if @version==1
        @creation_time = getInt64()
        @modification_time = getInt64()
        @timescale = getInt32()
        @duration = getInt64()
      else
        @creation_time = getInt32()
        @modification_time = getInt32()
        @timescale = getInt32()
        @duration = getInt32()
      end

      #bit(1) pad = 0;
      #unsigned int(5)[3] language; //
      language = getInt16
      language = (language << 1) & 0xFFFF
      @lang = ''

      3.times do
        l = (language >> 11) + 0x60
        @lang += l.chr
        language = (language << 5) & 0xFFFF
      end

      skipBox
    end
  end
  class HandlerBox < FullBox
    attr_accessor :handler_type

    def load
      @pre_defined = getInt32()
      @handler_type = get32BitString()
      # lets skip following fields
      #const unsigned int(32)[3] reserved = 0;
      #string name;
      skipBox
    end
  end
  class DataReferenceBox < FullBox
    def load
      entry_count = getInt32()
      raise InvalidFileException if entry_count != 1 # we don't support multi-source files
      box = FullBox.new(self, @file)
      raise InvalidFileException if box.flags != 1 # we don't support more-than-one-source files
      box.load
      @offset+= box.size
      skipBox
    end
  end
  class DataInformationBox < Box
    def load
      while @size > @offset && !@file.eof?
        box = Box.new(self, file)
        if 'dref' == box.type
          box = DataReferenceBox.new(self, box)
        else
          raise InvalidFileException
        end

        box.load
        @offset+= box.size
      end
      skipBox

    end
  end


  class SampleEntry < Box
    attr_accessor :data_reference_index, :codingname

    def initialize parent, arg
      super parent, arg
      # lets skip const unsigned int(8)[6] reserved = 0;
      @codingname = type()
      skipNBytes(6)
      @data_reference_index = getInt16()
    end
  end

  class AvcC < Box
    attr_accessor :sequesnceParameterSets, :pictureParameterSets
    def load
      # process according to this description http://thompsonng.blogspot.ru/2010/11/mp4-file-format-part-2.html
      raise "type incorrect" unless @type == "avcC"
      raise "wrong configuration version" unless getInt8() == 0x1
      skipNBytes(4)

      numOfSequesnceParameterSets = getInt8() & 0b11111 # get 5 lowest bits
      @sequesnceParameterSets = []
      numOfSequesnceParameterSets.times do
        sequenceParameterSetLength = getInt16
        @sequesnceParameterSets << getByteArray(sequenceParameterSetLength)
      end

      @pictureParameterSets = []
      numOfPictureParameterSets = getInt8()
      numOfPictureParameterSets.times do
        numOfPictureParameterSetLength = getInt16
        @pictureParameterSets << getByteArray(numOfPictureParameterSetLength)
      end
      skipBox
    end

  end

  class VisualSampleEntry < SampleEntry
    attr_accessor :width, :height, :compressorname

    def load
      pre_defined = getInt16
      reserved = getInt16
      pre_defined = getInt32Array(3)
      @width  = getInt16
      @height = getInt16
      horizresolution = getInt32
      vertresolution  = getInt32
      reserved = getInt32
      frame_count = getInt16
      raise InvalidFileException if frame_count != 1
      @compressorname = getFixedSizeString(32)
      depth = getInt16
      pre_defined = getInt16

      # lets get avcC params
      raise "wrong avc1 container" unless @size > @offset + 4         + 4
      parent.avcC =  box = AvcC.new(self, @file)
      box.load
      @offset+= box.size

      skipBox
    end
  end

  class AudioSampleEntry < SampleEntry
    attr_accessor :channelcount, :samplesize, :samplerate
    def load
      reserved = getInt32Array(2)
      @channelcount = getInt16
      @samplesize = getInt16
      pre_defined = getInt16
      reserved = getInt16
      @samplerate = getInt32
      skipBox
    end
  end

  # stts
  class TimeToSampleBox < FullBox
    attr_accessor :time_2_sample_info

    def load
      entry_count = getInt32
      @time_2_sample_info = []
      entry_count.times do
        @time_2_sample_info << [getInt32, getInt32]
      end
      skipBox
    end
  end

  # ctts
  class CompositionOffsetBox < FullBox
    attr_accessor :composition_sample_info
    def load
      entry_count = getInt32
      @composition_sample_info = []
      entry_count.times do
        @composition_sample_info << [getInt32, getInt32]
      end
      skipBox
    end
  end

  #stss
  class SyncSampleBox < FullBox
    attr_accessor :sync_sample_info
    def load
      entry_count = getInt32
      @sync_sample_info = []
      entry_count.times do
        @sync_sample_info << getInt32
      end
      skipBox
    end
  end

  # 'stsd'
  class SampleDescriptionBox < FullBox
    attr_accessor :vide, :soun, :avcC

    def load
                    #stbl  ->minf ->mdia ->trak
      handler_type = parent.parent.parent.handler.handler_type
      entry_count = getInt32()
      raise InvalidFileException if entry_count != 1
      if handler_type == 'vide'
        @vide = box = VisualSampleEntry.new self, @file
      else  handler_type == 'soun'
        @soun = box = AudioSampleEntry.new self, @file
      end
      box.load
      @offset+= box.size
      skipBox
    end
  end

  # stsc
  class SampleToChunkBox < FullBox
    attr_accessor :sample_info
    def load
      entry_count = getInt32
      @sample_info = []
      entry_count.times do
                        # first_chunk            samples_per_chunk  sample_description_index
        @sample_info << [getInt32,               getInt32,          getInt32]
      end
      skipBox
    end
  end

  # stsz
  class SampleSizeBox < FullBox
    attr_accessor :sample_size, :sample_count, :sample_sizes
    def load
      @sample_size  = getInt32
      @sample_count = getInt32
      if @sample_size == 0
        @sample_sizes = []
        @sample_count.times do
          @sample_sizes << getInt32
        end
      end
    end
  end

  # stco
  class ChunkOffsetBox < FullBox
    attr_accessor :chunk_offsets
    def load
      entry_count = getInt32
      @chunk_offsets = []
      entry_count.times do
        @chunk_offsets << getInt32
      end
    end
  end

  # co64
  class ChunkLargeOffsetBox < FullBox
    attr_accessor :chunk_offsets
    def load
      entry_count = getInt32
      @chunk_offsets = []
      entry_count.times do
        @chunk_offsets << getInt64
      end
    end
  end

  # stbl
  class SampleTableBox < Box
    attr_accessor :stsd, :stts, :ctts, :stss, :stsc, :stsz, :stco, :co64
    def load
      while @size > @offset && !@file.eof?
        box = Box.new(self, file)
        if 'stsd' == box.type
          @stsd = box = SampleDescriptionBox.new(self, box)
        elsif 'stts' == box.type
          @stts = box = TimeToSampleBox.new(self, box)
        elsif 'ctts' == box.type
          @ctts = box = CompositionOffsetBox.new(self, box)
        elsif 'stss' == box.type
          @stss = box = SyncSampleBox.new(self, box)
        elsif 'stsc' == box.type
          @stsc = box = SampleToChunkBox.new(self, box)
        elsif 'stsz' == box.type
          @stsz = box = SampleSizeBox.new(self, box)
        elsif 'stco' == box.type
          @stco = box = ChunkOffsetBox.new(self, box)
        elsif 'co64' == box.type
          @co64 = box = ChunkLargeOffsetBox.new(self, box)
        end
        box.load
        @offset+= box.size
      end

      # minf ->mdia ->trak
      handler_type = parent.parent.handler.handler_type
      if handler_type == 'vide'
        raise InvalidFileException unless @stsd && @stts && @stss && @stsc && @stsz && (@stco || @co64)
      elsif  handler_type == 'soun'
        raise InvalidFileException unless @stsd && @stts && !@stss && !@ctts && @stsc && @stsz && (@stco || @co64)
      end

      skipBox
    end
  end

  # minf
  class MediaInformationBox < Box
    attr_accessor :stbl
    def load
      while @size > @offset && !@file.eof?
        box = Box.new self, file
        if 'dinf' == box.type
          box = DataInformationBox.new self,  box
        elsif 'stbl' == box.type
          @stbl = box = SampleTableBox.new self, box
        end

        box.load
        @offset+= box.size
      end
      skipBox
    end
  end

  # mdia
  class MediaBox < Box
    attr_accessor :mdhd, :handler, :minf
    def load
      while @size > @offset && !@file.eof?
        box = Box.new(self, file)
        if 'mdhd' == box.type
          @mdhd = box = MediaHeaderBox.new(self, box)
        elsif 'hdlr' == box.type
          @handler = box = HandlerBox.new(self, box)
        elsif 'minf' == box.type
          @minf = box = MediaInformationBox.new(self, box)
        end
        box.load
        @offset+= box.size
      end
      skipBox
    end
  end

  # trak
  class TrackBox < Box
    attr_accessor :tkhd, :mdia

    def load
      while @size > @offset && !@file.eof?
        box = Box.new(self, file)
        if 'tkhd' == box.type
          @tkhd = box = TrackHeaderBox.new(self, box)
        elsif 'mdia' == box.type
          @mdia = box = MediaBox.new(self, box)
        end
        box.load
        @offset+= box.size
      end
      skipBox
    end
  end

  # moov
  class MovieBox < Box
   attr_accessor :mvhd, :traks

   def load
     @mvhd = nil
     @traks = []
     while @size > @offset && !@file.eof?
       box = Box.new(self, file)
       if 'mvhd' == box.type
         @mvhd = box =  MovieHeaderBox.new(self, box)
       elsif 'trak' == box.type
         @traks << box = TrackBox.new(self, box)
       end

       box.load
       @offset+= box.size
     end
     skipBox
   end
  end

  def load fileName
    File.open fileName, 'rb' do |file|
      while not file.eof? do
        box = Box.new(self, file)

        if 'ftyp' == box.type
          box = @fileType = FileTypeBox.new(self, box)
        elsif 'moov' == box.type
          box = @movieBox = MovieBox.new(self, box)
        end
        box.load
      end
    end
  end

  attr_accessor :fileType, :movieBox

end


def getMediaInfo(mediaFile)
  p "Movie Info creation_time= #{mediaFile.movieBox.mvhd.creation_time}"\
  ",modification time=#{mediaFile.movieBox.mvhd.modification_time}"\
  ",timescale=#{mediaFile.movieBox.mvhd.timescale}"\
  ",duration=#{mediaFile.movieBox.mvhd.duration}"

  mediaFile.movieBox.traks.each do |trak|
    p "Trak info Id=#{trak.tkhd.track_ID}"\
    ",duration=#{trak.tkhd.duration}"\
    ",width=#{trak.tkhd.width}"\
    ",height=#{trak.tkhd.height}"
    p "Media Header box. lang=#{trak.mdia.mdhd.lang}"
    p "Media Handler box.handler_type=#{trak.mdia.handler.handler_type}"
    next unless trak.mdia.handler.handler_type == 'vide' or trak.mdia.handler.handler_type == 'soun'

    stbl = trak.mdia.minf.stbl
    if stbl.stsd.vide
      p "Sample description box width=#{stbl.stsd.vide.width}"\
    ",height=#{stbl.stsd.vide.height}"\
    ",compressorname=#{stbl.stsd.vide.compressorname}"
    elsif stbl.stsd.soun
      p "Sample description channelcount=#{stbl.stsd.soun.channelcount}"\
    ",samplesize=#{stbl.stsd.soun.samplesize}"\
    ",samplerate=#{stbl.stsd.soun.samplerate}"
    end
    p "------------------------------------------------"
  end


end

p "wrong parameter count. add mp4 file and output directory" and exit if ARGV.length == 0 or ARGV.length > 2
mediaFile = IsoBaseMediaFile.new
mediaFile.load(ARGV[0])

getMediaInfo(mediaFile)

if ARGV[1]
  Dir.mkdir ARGV[1] unless Dir.exist? ARGV[1]

  mediaFile.movieBox.traks.each do |trak|
    Dir.mkdir "#{ARGV[1]}/#{trak.tkhd.track_ID}" unless Dir.exist? "#{ARGV[1]}/#{trak.tkhd.track_ID}"
    stbl = trak.mdia.minf.stbl

    chunk_id = 1
    chunk_samples = 0
    stsc_index = 0
    chunk_offset_table = stbl.stco ? stbl.stco.chunk_offsets  : stbl.co64.chunk_offsets
    chunks_count = chunk_offset_table.size
    offset_in_chunk = 0

    stbl.stsz.sample_count.times do |sample_id|
      sample_size = stbl.stsz.sample_size != 0 ? stbl.stsz.sample_size : stbl.stsz.sample_sizes[sample_id]

      stsc_item = stbl.stsc.sample_info[stsc_index]
      chunk_samples+= 1
      if chunk_samples > stsc_item[1] # second element is samples-per-chunk
        chunk_id+= 1
        chunk_samples=1
        offset_in_chunk = 0
      end

      raise "chunk_id > total chunk count" if chunk_id > chunks_count

      if stbl.stsc.sample_info[stsc_index + 1] && stbl.stsc.sample_info[stsc_index + 1][0] == chunk_id
        chunk_samples= 1
        stsc_index+= 1
        offset_in_chunk = 0
      end

      chunk_offset = chunk_offset_table[chunk_id -1]

      File.open "#{ARGV[1]}/#{trak.tkhd.track_ID}/#{sample_id}", 'wb' do |file_output|
        File.open ARGV[0], 'rb' do |file_input|

          file_input.seek(chunk_offset + offset_in_chunk, IO::SEEK_SET)
          offset_in_chunk+=sample_size
          file_output.write(file_input.read(sample_size))
        end
      end

    end
  end
end
