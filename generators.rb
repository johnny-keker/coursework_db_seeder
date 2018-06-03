%w(
  static utils
  person house study_plan subject student_club student_profile
  delivery_owls delivery_owl_flights
  creatures
  spells
  books book_lendings
).each { |s| require_relative s }
require 'pry'

def run_all_generators
  # Generators should run in the order they are defined in source.
  generators = Generators.methods(false).map { |m| Generators.method(m) }.sort_by { |m| m.source_location.last }
  #binding.pry

  data = OpenStruct.new({
    students: [], study_plans: [], subjects: [], student_clubs: [], student_profiles: [],
    delivery_owls: [], delivery_owl_flights: [],
    current_house: OpenStruct.new
  })

  Static.houses.each { |house| generators.each { |g| g.call data, house } }

  data
end

STUDENTS_PER_HOUSE = 100
PLANS_PER_YEAR = 4
STUDENTS_PER_CLUB = 8
OWLS_PER_HOUSE = 10
CREATURES_AMOUNT = 20
SPELLS = 20
FLIGHTS = 20
BOOKS = 20

module Generators
  class << self
    def houses(data, _house)
      data.houses ||= [
        House['Gryffindor', 1, '{"courage", "bravery"}'],
        House['Hufflepuff', 2, '{"hard work", "patience", "justice", "loyalty"}'],
        House['Ravenclaw', 3, '{"intelligence", "creativity", "wit"}'],
        House['Slytherin', 4, '{"ambition", "cunning", "leadership", "resourcefulness"}']
      ]
    end

    def people_deans(data, _house)
      data.teachers ||= [
        Person['Minerva McGonagall', '1931-10-04'.to_datetime, nil, 'courage', 'female', "Gryffindor's Dean"],
        Person['Pomona Sprout', '1941-05-15'.to_datetime, nil, 'hard work', 'female', "Hufflepuff's Dean"],
        Person['Filius Flitwick', '1958-10-17'.to_datetime, nil, 'wit', 'male', "Ravenclaw's Dean"],
        Person['Severus Snape', '1960-01-06'.to_datetime, nil, 'leadership', 'male', "Slytherin's Dean"]
      ]
    end

    def student_activity(data, house)
      students = Person.make_many house,
        birth_from: '2001-1-1', birth_to: '2007-12-31', count: STUDENTS_PER_HOUSE
      study_plans, plan_id_to_student_id = StudyPlan.make_many house, students,
        max_plans_per_year: PLANS_PER_YEAR, study_plan_id_offset: data.study_plans.size + 1,
        student_id_offset: data.students.size + 1
      teachers = Person.make_many house,
        birth_from: '1950-1-1', birth_to: '1990-1-1', count: Subject.teacher_count_required(PLANS_PER_YEAR)
      plan_id_to_subject_id = Subject.make_many teachers, study_plans,
        teacher_count_multiplier: PLANS_PER_YEAR, study_plan_id_offset: data.study_plans.size + 1

      data.current_house.student_ids = (data.students.size + 1)..(data.students.size + students.size)
      data.students += students
      data.teachers += teachers

      student_clubs, student_id_to_club_id = StudentClub.make_many_and_assign_membership data.current_house.student_ids,
        students_per_club: STUDENTS_PER_CLUB, club_id_offset: data.student_clubs.size + 1
      student_profiles = StudentProfile.make_all plan_id_to_student_id, student_id_to_club_id
   
      # This is important! Student clubs are generated prior to profiles, and their #president_id
      # refers to an entry in `people`, not `student_profiles` as it should.
      # 
      # Now that we have profiles, we build up a hash of { person id => profile id } and use it
      # to reassign club president ids.
      profile_ids_students, _ = student_profiles.reduce([{}, data.student_profiles.size + 1]) do |(acc, current_profile_id), p| 
        acc[p.person_id] = current_profile_id
        [acc, current_profile_id + 1]
      end
      student_clubs.each { |c| c.president_id = profile_ids_students[c.president_id] }

      data.study_plans += study_plans
      data.subjects += plan_id_to_subject_id.values.flatten(1)
      data.student_clubs += student_clubs
      data.student_profiles += student_profiles
    end

    def delivery_owls(data, house)
      first_owl_id = data.delivery_owls.size + 1
      owls = DeliveryOwl.del_owls(Static.house_id(house), OWLS_PER_HOUSE)

      data.delivery_owls += owls
      data.current_house.owl_ids = first_owl_id..(first_owl_id + owls.size)
    end

    def creatures(data, _house)
      data.creatures ||= Creature.get_creatures(CREATURES_AMOUNT)
    end

    def spells(data, _house)
      data.spells ||= Spell.get_spells(SPELLS, 1..data.teachers.size)
    end

    def delivery_owl_flights(data, house) #FIXME
      data.delivery_owl_flights += DeliveryOwlFlight.get_flights(FLIGHTS,
         data.current_house.owl_ids, data.current_house.student_ids)
    end

    def books(data, _houses)
      data.books ||= Book.get_books(BOOKS)
    end

    def book_lendings(data, house) #FIXME
      return unless house == Static.houses.last
      data.book_lendings = BookLending.get_lendings(data.books, 
        (data.teachers.size + 1)..(data.students.size + data.teachers.size), 1..data.teachers.size)
    end

  end
end
