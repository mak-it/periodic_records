module PeriodicRecords
  module Model
    extend ActiveSupport::Concern

    MIN = Date.new(0001, 1, 1)
    MAX = Date.new(9999, 1, 1)

    included do
      validates_presence_of :start_at, :end_at
      validate :validate_dates

      after_initialize :set_default_period, if: :set_default_period_after_initialize?
      before_save :adjust_overlapping_records
    end

    module ClassMethods
      def within_interval(start_date, end_date)
        t = arel_table
        where(t[:start_at].lteq(end_date)).
        where(t[:end_at].gteq(start_date))
      end

      def within_date(date)
        within_interval(date, date)
      end

      def current
        date = Date.current
        within_date(date)
      end

      def from_date(date)
        t = arel_table
        where(t[:end_at].gteq(date))
      end
    end

    def current?
      date = Date.current
      within_interval?(date, date)
    end

    def within_interval?(start_date, end_date)
      start_at && end_at && start_at <= end_date && end_at >= start_date
    end

    def siblings
      raise NotImplementedError
    end

    def overlapping_records
      siblings.within_interval(start_at, end_at)
    end

    def adjust_overlapping_records
      overlapping_records.each do |overlapping_record|
        if overlapping_record.start_at >= start_at &&
             overlapping_record.end_at <= end_at
          destroy_overlapping_record(overlapping_record)
        elsif overlapping_record.start_at < start_at &&
                overlapping_record.end_at > end_at
          split_overlapping_record(overlapping_record)
        elsif overlapping_record.start_at < start_at
          adjust_overlapping_record_end_at(overlapping_record)
        elsif overlapping_record.end_at > end_at
          adjust_overlapping_record_start_at(overlapping_record)
        end
      end
    end

    def set_default_period_after_initialize?
      new_record?
    end

    def periodic_dup
      dup
    end

    def record_split_step
      @record_split_step ||= begin
        column = self.class.column_for_attribute(:start_at)
        if column.type == :datetime
           precision = column.precision || 6
           Float("1.0e-#{precision}").seconds
        else
          1.day
        end
      end
    end

    private

    def set_default_period
      self.start_at ||= Date.current
      self.end_at   ||= MAX
    end

    def destroy_overlapping_record(overlapping_record)
      overlapping_record.destroy
    end

    def split_overlapping_record(overlapping_record)
      overlapping_record_end = overlapping_record.periodic_dup
      overlapping_record_end.start_at = end_at + record_split_step
      overlapping_record_end.end_at   = overlapping_record.end_at

      overlapping_record_start = overlapping_record
      overlapping_record_start.end_at = start_at - record_split_step

      overlapping_record_start.save(validate: false)
      overlapping_record_end.save(validate: false)
    end

    def adjust_overlapping_record_end_at(overlapping_record)
      overlapping_record.end_at = start_at - record_split_step
      overlapping_record.save(validate: false)
    end

    def adjust_overlapping_record_start_at(overlapping_record)
      overlapping_record.start_at = end_at + record_split_step
      overlapping_record.save(validate: false)
    end

    def validate_dates
      if start_at && end_at && end_at < start_at
        errors.add :end_at, :invalid
      end
    end
  end
end
