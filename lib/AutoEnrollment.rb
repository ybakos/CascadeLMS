require 'CourseCreator'
class AutoEnrollment < CourseCreator
  
  def initialize( user, crns, descs, format  )
    super( user, crns, descs, format )
  end
  
  def reconcile
    status = ""
    
    ## then verify that (1) the courses exist and (2) this use is an instructor
    @crns.each_index do |i|
      crn_txt = @crns[i]
      description = @subjects[i]
      crn = Crn.find(:first, :conditions => ["crn = ?", crn_txt] )
      
      unless crn.nil?
        # enroll this user (as a student) in each course this CRN points to
        crn.courses.each do |course|
        
          found = false
          course.courses_users.each do |cu|
            if cu.user_id == @user.id
              if cu.crn_id == 0
                cu.crn_id = crn.id
                cu.save
              end
              
              unless cu.course_student
                unless cu.dropped
                  cu.course_student = true
                  cu.save
                end
              end
              found = true
            end
          end
        
          # if we didn't find the user, enroll them
          unless found
            courseuser = CoursesUser.new
            courseuser.user = @user
            courseuser.course = course
            courseuser.course_student = true
            courseuser.course_instructor = false
            courseuser.term_id = course.term_id
            courseuser.crn_id = crn.id
        
            courseuser.save
            status = "#{status} You have been enrolled in the course: #{course.title} (#{crn.crn}, #{crn.name}).<br/>"
          end
        end
      end
    end
    
    status = nil if status.eql?('')
    return status
    
  end
  
end