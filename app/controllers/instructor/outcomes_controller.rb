class Instructor::OutcomesController < Instructor::InstructorBase
  
  before_filter :ensure_logged_in
  before_filter :set_tab
 
  def index
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
  
    # build list of available programs, filter out ones that this course is already a part of
    all_programs = Program.find(:all, :order => "title asc")
    @programs = Array.new
    all_programs.each do |program|
      add = true
      @course.programs.each do |course_program| 
        add = false if program.id == course_program.id
      end
      @programs << program if add
    end
  
    set_title
  end
  
  def map_program
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
    
    @program = Program.find(params[:program_id]) rescue @program = nil
    
    @course.programs << @program
    if @course.save
        set_highlight = "program_#{@program.id}"
        flash[:notice] = 'New course to program mapping saved.'
        redirect_to :action => 'index', :course => @course
    else
      render :action => 'index', :course => @course
    end
  end
  
  def unmap_program
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
    
    @program = Program.find(params[:program]) rescue @program = nil
    
    course_program = CoursesPrograms.find(:all, :conditions => ["course_id = ? and program_id = ?", @course.id, @program.id])
    course_program.each do |i|
      i.destroy
    end
    
    render :nothing => true    
  end
  
  def edit
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
    
    @course_outcome = CourseOutcome.find(params[:id])
    
  end
  
  def update_outcome
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
    
    @course_outcome = CourseOutcome.find(params[:id])
    # first - pull the outcome text
    @course_outcome.outcome = params[:course_outcome][:outcome]
    
    old_parent = @course_outcome.parent
    new_parent = params[:parent].to_i
    
    # pre-load the possible program outcomes
    program_outcomes = load_program_outcomes( @course )
    
    CourseOutcome.transaction do
      @course_outcome.program_outcomes.clear
      @course_outcome.save
      program_outcomes.each do |program_outcome|
         @course_outcome.program_outcomes << program_outcome unless params["program_outcome_#{program_outcome.id}"].nil? 
      end
      
      # if hierarchy is changing - we have to recalculate both the old parent's child ordering
      # and the new parent's child ordering
      if old_parent != new_parent 
        
        position = 1
        @course.extract_outcome_by_parent( @course.course_outcomes, old_parent ).each do |outcome|
          if outcome.id != @course_outcome.id
            outcome.position = position
            position = position.next
            # update
            outcome.save
          end
        end
        
        position = 1
        @course.extract_outcome_by_parent( @course.course_outcomes, new_parent ).each do |outcome|
          if outcome.id != @course_outcome.id
            outcome.position = position
            position = position.next
            # update
            outcome.save
          end
        end
        
        # update record being edited
        @course_outcome.position = position
        @course_outcome.parent = new_parent
        
      end
      
      
      @course_outcome.save
      
      flash[:notice] = 'Your outcome changes have been saved.'
      return redirect_to :action => 'index', :course => @course
    end
    render :action => 'edit', :course => @course, :id => params[:id]
  end
  
  def new
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
    
    @course_outcome = CourseOutcome.new
  end
  
  def create_outcome
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
    
    @course_outcome = CourseOutcome.new(params[:course_outcome])
    @course_outcome.course = @course
    @course_outcome.parent = params[:parent].to_i
    
    # find out what position this one should be
    at_level = @course.extract_outcome_by_parent( @course.course_outcomes, @course_outcome.parent ) 
    next_position = 1
    next_position = at_level[-1].position + 1 if at_level.length > 0
    @course_outcome.position = next_position
    
    # find the program outcomes that map
    program_outcomes = load_program_outcomes( @course )
    
    CourseOutcome.transaction do 
      if @course_outcome.save
        program_outcomes.each do |program_outcome|
           @course_outcome.program_outcomes << program_outcome unless params["program_outcome_#{program_outcome.id}"].nil? 
        end
        @course_outcome.save

        set_highlight = "course_outcome_#{@course_outcome.id}"
        flash[:notice] = 'New course outcome has been saved.'
        redirect_to :action => 'index', :course => @course
      else
        render :action => 'new', :course => @course
      end
    end
  end
  
  def reorder
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
    
    # get the outcomes at this level
    @course_outcomes = @course.extract_outcome_by_parent( @course.course_outcomes, params[:id].to_i ) 
    @parent = params[:id]
    
    @parent_outcome = CourseOutcome.find(@parent) if @parent != -1 rescue @parent_outcome = nil  
  end
  
  def sort
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
    
    # get the outcomes at this level
    @course_outcomes = @course.extract_outcome_by_parent( @course.course_outcomes, params[:id].to_i ) 
    CourseOutcome.transaction do
      @course_outcomes.each do |outcome|
        outcome.position = params['outcome-order'].index( outcome.id.to_s ) + 1
        outcome.save
      end
    end
    
    render :nothing => true
  end
  
  def destroy
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_edit_outcomes' )
    
    @course_outcome = CourseOutcome.find(params[:id])
    children = @course_outcome.child_outcomes
    
    CourseOutcome.transaction do
      if children.length > 0
        parents_children = @course.extract_outcome_by_parent( @course.course_outcomes, @course_outcome.parent )
        position = parents_children.length + 1
        
        children.each do |child|
          child.parent = @course_outcome.parent
          child.position = position
          position = position.next
          child.save
        end       
      end
      
      @course_outcome.destroy
    end
    
    
    redirect_to :action => 'index', :course => @course
  end

private
  def set_title
    @title = "Course Outcomes - #{@course.title}"
  end
  
  def load_program_outcomes( course )
    program_outcomes = Array.new
    course.programs.each do |program|
      program.program_outcomes.each do |prog_outcome|
        program_outcomes << prog_outcome
      end
    end
    return program_outcomes
  end
  
end
